+++
title = "Analyzer Architecture"
description = "How Noir's detectors, language engines, route extractors, and framework adapters fit together, and how to add a new analyzer."
weight = 5
sort_by = "weight"

+++

Noir scans a project in two phases. A **detector** decides which frameworks are present, then an **analyzer** extracts endpoints for each detected framework. This page shows how the analyzer side is laid out and how to add a new framework.

If you only want to add a framework, start at [Adding a new framework](#adding-a-new-framework). The sections before it describe the structure your code plugs into.

## Pipeline overview

```
project files
      │
      ▼
  Detector         ──►  "this project uses go_gin, go_hertz, …"
      │
      ▼
  Analyzer         ──►  list of Endpoint (url, method, params, details)
      │
      ▼
  Optimizer, Taggers, Passive scan, Output formatter
```

A detector does a cheap match (usually on a manifest file like `go.mod`, `package.json`, `Gemfile`) and returns a boolean. An analyzer does the heavy work: walks the source tree, parses route declarations, extracts parameters.

## The 3-layer analyzer

Every analyzer has three layers. Keep them separate: a framework adapter should not open files or re-implement parsing.

| Layer | Lives in | Responsibility |
|---|---|---|
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | The language's source-file set, per-path filters, the worker pool and the content cache. One per language. Eight engines get the walk itself from `FileScanEngine`. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor*.cr` | Parses source content. Takes a string (file contents), yields route declarations (method, path, location). No file I/O, no framework-specific rules. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | Thin per-framework class. Consumes routes from the extractor and applies framework-specific param mappings, filters, and special cases. |

`spec/unit_test/analyzer/layering_boundary_spec.cr` enforces the file-walking half of this rule: `Dir.glob`, `Dir.children` or `Dir.each_child` anywhere under `src/analyzer/analyzers/` fails the suite.

Get your file set from the engine or from the detector-built indexes (`get_files_by_extension`, `CodeLocator#files_by_basename`). Walking a directory yourself skips subtree pruning, `--exclude-path`, the media filter and the content cache.

**Reference implementations.** No single file is the whole model yet. Take the walk from one and the body from the other:

- **The walk (L0)**: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr) inherits `JavascriptEngine` and drives the walk with `ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS))`. It gets the worker pool, content cache and per-file error isolation for free, and per-file results come back in input order. Don't copy its body: it still carries its own regex passes next to the extractor call.
- **The body (L1 → L2)**: [`javascript/hapi.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hapi.cr) is about 65 lines. It rides `JavascriptEngine` with the same `ordered_scan_files` walk, calls `Noir::TreeSitterHapiExtractor.extract_routes`, and only maps the result onto `Param`s. `javascript/elysia.cr`, `javascript/adonisjs.cr`, `kotlin/http4k.cr` and `java/spark.cr` have the same body, but don't copy their walk: those four extend `Analyzer` directly and loop over `all_files` themselves.

## Current coverage

- **Language engines** (in `engines/`): Specification, JavaScript/TypeScript, Go, Python, PHP, Rust, Ruby, Crystal, CFML, Scala, Swift, Perl, C, Elixir.
- **`FileScanEngine`** sits under eight of those (C, Crystal, Elixir, Perl, PHP, Rust, Scala, Swift) and owns the `analyze` + `parallel_file_scan` skeleton they used to each carry a copy of.
- `java_engine.cr` and `kotlin_engine.cr` are **not** engines despite the filenames. No analyzer inherits from them.
  - `KotlinEngine` only exposes a shared `self.test_path?`.
  - `JavaEngine` is also a mixin (a module a class `include`s) that JVM adapters use for shared helpers (JAX-RS indexes, Spring/Micronaut/Quarkus config readers).
  - `PlayRouteSupport` and `CliEndpointSupport` are mixins of the same kind.
- **Route extractors** (in `miniparsers/`):
  - JavaScript: `js_route_extractor.cr`. Express, Fastify, Hono, Koa and Restify get their routes from `JSRouteExtractor.extract_routes`. NestJS, Next.js, Nuxt and others use only its helpers.
  - Tree-sitter extractors for Go, Java, Kotlin and Python. Go and Kotlin ship as directories of part files behind an umbrella `require` (`go_route_extractor_ts/`, `kotlin_route_extractor_ts/`).
  - Framework-specific Tree-sitter extractors: AdonisJS, Elysia, Hapi, http4k, JAX-RS, Micronaut, Ktor, and others.
- **Outside the engine stack**: C#, VB.NET, F#, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua, Groovy, Erlang, Gleam, R, Apex, Classic ASP and WebForms, plus Scala Play, Go's Chi, Httprouter, Fasthttp and Kratos, JavaScript's AdonisJS and Elysia, Elixir's Phoenix channels, and the Android/iOS mobile analyzers. Their analyzers orchestrate multiple phases or carry self-contained extraction, so they inherit from `Analyzer` directly.

## Engine walk helpers

There is no single walk API shared by every engine. Check what your language's engine offers before you write an adapter:

| Engine | What the adapter uses |
|---|---|
| `FileScanEngine` engines (C, Crystal, Elixir, Perl, PHP, Rust, Scala, Swift) | The engine supplies the candidate list through `scan_target_files` and an optional per-path veto through `scan_accepts?`. The adapter implements `analyze_file` (shape A below) |
| JavaScript and Ruby engines | They define their own `parallel_file_scan` and have no `scan_target_files`. The adapter overrides `analyze` and calls `parallel_file_scan`, or `ordered_scan_files` over `get_files_by_extensions(...)` to get per-file results back in input order (shape B below) |
| `PythonEngine` | Language-specific iterators: `python_source_files` / `each_python_source` / `parallel_python_sources` |
| `SpecificationEngine` | Language-specific iterators: `each_spec_file` / `each_spec_file_with_details` |
| `CfmlEngine` | Language-specific iterators: `cfml_components` / `cfml_pages` |
| `GoEngine` | Whole-package content through `read_package_file_contents` and the `collect_*` helpers. Most adapters walk with `parallel_analyze`; `hertz.cr` and `encore.cr` use `ordered_parallel_analyze`, which returns results in input order and is the one to use in new code |
| No engine | The adapter extends `Analyzer` and uses `scan_files(files, &block)`, the shared skeleton every engine above funnels into |

**Shape A: `analyze_file`** (simpler, pure per-file):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # parse, build endpoints, return them
  end
end
```

`FileScanEngine#analyze` drives the walk and merges the returned endpoints in input order. Most PHP, Rust, Swift, Crystal, Elixir and Scala analyzers use this shape.

**Shape B: custom `analyze`** (for closure state, pre- or post-phases):

```crystal
class MyFramework < JavascriptEngine
  def analyze
    per_file = ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
      endpoints = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      # ... parse this one file into endpoints and static_dirs
      {endpoints, static_dirs}
    end

    per_file.each { |endpoints, _| result.concat(endpoints) }
    process_js_static_dirs(per_file.flat_map(&.[1]), result)  # post-pass
    result
  end
end
```

Use this when the analyzer needs state across files or a post-processing pass. Express, Hono, Rails and Amber are examples. Read the execution model note at the end of this page before sharing state between workers.

## Adding a new framework

This walkthrough uses **Hertz (Go)** as the example. Real PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

Create `src/detector/detectors/{language}/{framework}.cr`. Detectors are almost always a one-line match:

```crystal
require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end
  end
end
```

- `detector_for` declares the tech name once. It also generates `applicable?`, a cheap file gate that decides which files `detect` is even offered. The gate keys are `extensions:`, `basenames:` and `path_segments:`.
- If `detect` has side effects (registering spec paths in `CodeLocator`, say), also pass `idempotent: false` so the pass keeps calling it after its first match.
- The detector runs once per candidate file. Returning `true` marks the framework as present and tells the pipeline to run the matching analyzer.

Add a unit spec at `spec/unit_test/detector/{language}/{framework}_spec.cr`. It is required: `spec/unit_test/techs/detector_coverage_spec.cr` fails for a detector without one.

### 2. Analyzer

Create `src/analyzer/analyzers/{language}/{framework}.cr` and inherit from the language engine. Hertz routes like Gin, so it shares most of Gin's structure:

```crystal
require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    analyzer_for "go_hertz"

    HTTP_METHODS_EXPANDED = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]
    IMPORT_MARKER         = "github.com/cloudwego/hertz"

    def analyze
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)

      per_file = ordered_parallel_analyze(get_files_by_extension(".go")) do |path|
        content = file_contents[path]? || read_file_content(path)
        cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
        routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle")
        # ... turn routes into endpoints, then per-line param extraction
        {file_endpoints, file_public_dirs}
      end

      per_file.each { |file_endpoints, _| result.concat(file_endpoints) }
      resolve_public_dirs(per_file.flat_map(&.[1]))
      result
    end
  end
end
```

What to take from this example:

- **Inherit from the language engine** (`GoEngine` here). You get `collect_package_groups_ts`, `ts_groups_for_directory`, `add_param_to_endpoint` and `resolve_public_dirs` for free.
- **Declare the tech with `analyzer_for`**. That single line *is* the registration (see step 3). Leaving it out is a compile error.
- **Delegate route parsing to the shared extractor** (`Noir::TreeSitterGoRouteExtractor`). If your framework routes differently, steer the extractor with its arguments (e.g. `handle_method:`) or its specialized entry points instead of re-parsing (see Mux or GoZero).
- **Use the engine's walk helper** (`ordered_parallel_analyze(get_files_by_extension(".go"))` for Go, `ordered_scan_files`, `parallel_file_scan` or `analyze_file` elsewhere). Don't re-implement the channel and worker pool.
- **Only list verbs the framework actually routes** in your method table. In particular, add `QUERY` (RFC 10008) only when upstream ships explicit support for it. A speculative entry reports endpoints the framework itself answers with 405. The same goes for wildcard (`ANY`/`ALL`/`*`) routes. Don't add `QUERY` to the shared `WILDCARD_HTTP_METHODS` (`src/utils/http_symbols.cr`) or to the local tables some analyzers use to expand `ANY` themselves.

### 3. Declare the tech metadata

There is **no registration list to edit**. The analyzer and detector registries come from the classes themselves: `initialize_analyzers` (`src/analyzer/analyzer.cr`) and `build_detector_list` (`src/detector/detector.cr`) each sweep `all_subclasses` and read the name off `analyzer_for` / `detector_for`. Both lists used to be hand-maintained, and a forgotten entry produced no error and no failing spec, just a component that never ran.

What's left is the catalog entry: a new file at the same relative path as the analyzer and the detector.

```crystal
# src/techs/catalog/go/hertz.cr
#
# The directory is the language, the filename matches the analyzer's, and the
# constant is that filename upcased. `NoirTechs::TECHS` is macro-derived from
# every constant under `NoirTechs::Catalog`, so there is no list to append to
# and two people adding frameworks never touch the same file.
module NoirTechs::Catalog::Go
  HERTZ = {
    :go_hertz => {
      :framework => "Hertz",
      :language  => "Go",
      :similar   => ["hertz", "go-hertz", "go_hertz", "cloudwego"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => { :query => true, :path => true, :body => true, :header => true, :cookie => true },
        :static_path => false,
        :websocket   => false,
      },
      # Optional. Declares which AI-context capabilities this tech supports;
      # CALLEE_SUPPORTED_TECHS and AI_CONTEXT_GUARD_SUPPORTED_TECHS are derived
      # from these flags rather than hand-listed.
      :context => { :callee => true, :guards => true },
    },
  }
end
```

`spec/unit_test/techs/registry_integrity_spec.cr` checks the three-way link in both directions: every analyzer and detector has a catalog entry, and every catalog entry is backed by both. A missing catalog entry fails there rather than at runtime.

### 4. Fixture

Create `spec/functional_test/fixtures/{language}/{framework}/` with a minimal app:

```
spec/functional_test/fixtures/go/hertz/
├── go.mod            # import line the detector will match
├── main.go           # exercise every route/param pattern you care about
└── public/           # optional: for static-file detection
    └── index.html
```

The fixture should cover realistic patterns: path params, query/form/header/cookie, route groups, static serving, and framework-specific idioms (Hertz's `.Any` expands to all HTTP methods, Flask has blueprints, and so on). Don't try to be exhaustive. Add cases as real-world bugs surface.

### 5. Spec

Create `spec/functional_test/testers/{language}/{framework}_spec.cr`:

```crystal
require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  # ... etc
]

FunctionalTester.new("fixtures/go/hertz/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
```

The tester checks that:
- The detector finds exactly 1 tech (your framework).
- The analyzer produces exactly N endpoints (`expected_endpoints.size`).
- For each expected endpoint, an endpoint with the same URL and method exists in the output.
- For each expected param, a param with the same `name` and `param_type` is attached to that endpoint.

### 6. Verify

```bash
just build                 # compiles cleanly
just test                  # unit + functional spec pass
just check                 # crystal tool format --check + ameba

# Manual smoke test
./bin/noir scan spec/functional_test/fixtures/{lang}/{framework}
```

## Other components

Output formats and taggers register the same way: you annotate the class, and there is no list to edit.

- **Output format**: create `src/output_builder/{format}.cr` and annotate the class with `@[Noir::OutputFormat(name: "{format}", description: "…", order: 40)]`. `src/output_builder/formats.cr` builds the `-f` help text, `noir list formats` and the render dispatch from it. Add `spec/unit_test/output_builder/{format}_spec.cr`.
- **Tagger**: create `src/tagger/taggers/{name}.cr` (or `src/tagger/framework_taggers/{language}/{name}.cr` for a framework auth tagger, which inherits `FrameworkTagger`) and annotate it with `@[Noir::TaggerFor(key: "{name}", name: "…", desc: "…", order: 180)]`. `key` becomes the `--use-taggers` value. `order` fixes the order taggers run in, and so the order their tags are appended, so append a new value instead of renumbering. A missing annotation is not a compile error, but `registry_integrity_spec.cr` fails and names the class. Add a spec under `spec/unit_test/tagger/`.

## Adding a new language engine

When a language has 2+ analyzers that share a file-walk pattern, extract an engine. **Inherit from `FileScanEngine`**: it already owns the walk. Your engine declares only what is language-specific: which files to scan, which to skip, and any shared route-composition helpers.

```crystal
# src/analyzer/engines/swift_engine.cr
require "../../models/analyzer"

require "./file_scan_engine"

module Analyzer::Swift
  abstract class SwiftEngine < FileScanEngine
    # Candidate files. Prefer the detector-built extension index over
    # walking the whole `file_map`: these are registered regular files,
    # so no per-path `File.exists?` / `File.directory?` is needed.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".swift")
    end

    # Optional per-path veto. Runs on the scan-base-relative path, never
    # the absolute one: a convention filter that matches the absolute path
    # hands the decision to whatever directory the checkout happens to
    # live in, so the same tree reports different endpoints depending on
    # where it was cloned.
    protected def scan_accepts?(path : String) : Bool
      relative = base_relative_path(path)
      return false if relative.includes?("/Tests/")
      !relative.includes?("/.build/")
    end
  end
end
```

`FileScanEngine` supplies `analyze` (walk, call `analyze_file` per path, merge in input order), the `abstract def analyze_file(path) : Array(Endpoint)` contract, and `parallel_file_scan` / `ordered_file_scan` for subclasses that need a custom `analyze`. Don't re-implement the channel and worker pool: nine engines each carried an identical copy of it before [#2465](https://github.com/owasp-noir/noir/pull/2465) hoisted it, and a hand-rolled copy brings that duplication back.

When you add the engine, migrate the existing analyzers to inherit from it in the same PR. See [#1236](https://github.com/owasp-noir/noir/pull/1236) (Elixir), [#1237](https://github.com/owasp-noir/noir/pull/1237) (Swift) and [#1238](https://github.com/owasp-noir/noir/pull/1238) (Crystal) for worked examples.

## Adding a route extractor (L1)

When 2+ analyzers in a language share real parsing logic (not just file walking), move it into a route extractor under `src/miniparsers/`. Keep it pure: it takes source content and returns routes, with no `Analyzer` dependency and no file I/O.

```crystal
module Noir::MyLangRouteExtractor
  extend self

  record Route, method : String, path : String, line : Int32

  def extract_routes(content : String) : Array(Route)
    # pure parsing
  end
end
```

The adapter calls the extractor directly and maps the result onto endpoints, the way `hapi.cr` does with `Noir::TreeSitterHapiExtractor.extract_routes(content, include_callee)`. If the language already has an extractor, extend it instead of re-parsing inline.

Once an extractor outgrows one file, split it into a directory of part files behind an umbrella `require` rather than letting it grow: [`go_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/go_route_extractor_ts) is split by framework family, [`kotlin_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/kotlin_route_extractor_ts) by concern.

## Execution model note

In short: workers can finish in any order, so an analyzer's result must not depend on that order.

`parallel_analyze` workers (and everything built on it: `scan_files`, `parallel_file_scan`) are fibers on Crystal's default execution context. That context runs one scheduler, but when a worker sits in a slow syscall the runtime can hand the scheduler to another thread. Workers still run one at a time. However, a fiber can resume on a different thread, and the order they finish in changes from run to run.

Fibers on `Noir::WorkerThreads` are different: that pool really runs in parallel, so keep it to pure work that touches no shared state.

What that means for an analyzer:

- Don't let the result depend on which file finishes first. A merge where one file can override another (two services that define the same controller name, say) picks a different winner from run to run.
- Prefer returning per-file results over appending to shared state from workers. `FileScanEngine#analyze` already merges `analyze_file` results in input order. For a custom shape, use `ordered_file_scan`, `ordered_scan_files` or `ordered_parallel_analyze`, which hand back each file's result in input order.
- If code can be reached from `Noir::WorkerThreads`, guard any shared mutable collection with a `Mutex`.

Some older analyzers still append to a shared `result` from inside the walk. Don't copy that into new code. See [#2770](https://github.com/owasp-noir/noir/pull/2770) and [#2874](https://github.com/owasp-noir/noir/pull/2874) for the bugs that order dependence caused.

## Where to look next

- Walk (L0) reference: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- Thin adapter (L2) reference: [`javascript/hapi.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hapi.cr)
- Shared file-walk base: [`engines/file_scan_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/file_scan_engine.cr)
- Engine + extractor pair: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor_ts.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor_ts.cr)
- Custom-shape example: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (pre-phase + closure state)
- Framework-adapter example: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (first framework added after the engine refactor)
