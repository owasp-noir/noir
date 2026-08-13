+++
title = "Analyzer Architecture"
description = "How Noir's detectors, language engines, route extractors, and framework adapters fit together, and how to add a new analyzer."
weight = 5
sort_by = "weight"

+++

Noir scans a project in two phases: a **detector** decides which frameworks are present, and an **analyzer** extracts endpoints for each detected framework. This page explains how the analyzer side is laid out and how to add a new framework.

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

Every analyzer is composed of three layers. Keeping them separate is a hard rule: a framework adapter should not open files or re-implement parsing.

| Layer | Lives in | Responsibility |
|---|---|---|
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | The language's source-file set and per-path filters. One per language. Most engines get the walk itself from `FileScanEngine`, which owns `analyze` + `parallel_file_scan`; concurrency comes from `Analyzer#parallel_analyze`. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor*.cr` | Parses source content. Takes a string (file contents), yields route declarations (method, path, location). No file I/O, no framework-specific rules. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | Thin per-framework class. Consumes routes from the extractor and applies framework-specific param mappings, filters, and special cases. |

**Reference implementation**: [`src/analyzer/analyzers/javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr) on top of [`src/miniparsers/js_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/js_route_extractor.cr). It stays thin because it follows the split; contrast with analyzers that inline all three responsibilities.

## Current coverage

- **Language engines** (in `engines/`): Specification, JavaScript/TypeScript, Go, Python, PHP, Rust, Ruby, Crystal, CFML, Scala, Swift, Perl, Elixir.
- **`FileScanEngine`** sits *under* seven of those (Crystal, Elixir, Perl, PHP, Rust, Scala, Swift) and holds the file-walk skeleton they used to each carry a byte-identical copy of.
- `java_engine.cr` and `kotlin_engine.cr` are **not** engines despite the filenames — they are modules exposing a shared `self.test_path?`, and no analyzer inherits from them.
- **Route extractors** (in `miniparsers/`): JavaScript (`js_route_extractor.cr`, used by Hono, Express, Fastify, Koa, NestJS, Restify, AdonisJS, Elysia, Hapi and more) plus Tree-sitter extractors for Go, Java, Kotlin and Python. Go and Kotlin ship as directories of part files behind an umbrella `require` (`go_route_extractor_ts/`, `kotlin_route_extractor_ts/`).
- **Deliberately outside the engine stack**: languages whose analyzers orchestrate multiple phases or carry self-contained extraction — CSharp, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua, Groovy, Scala Play, and Go's Chi/Httprouter/Fasthttp. These inherit from `Analyzer` directly.

## Two engine shapes

Every engine exposes `parallel_file_scan(&block)` as a protected helper. A framework adapter picks one of two shapes:

**Shape A: `analyze_file`** (simpler, pure per-file):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # parse, build endpoints, return them
  end
end
```

`FileScanEngine#analyze` drives the walk and concats returned endpoints; the engine supplies the candidate list through `scan_target_files` and an optional per-path veto through `scan_accepts?`. Used by most Php / Rust / Swift / Crystal / Elixir / Scala analyzers.

**Shape B: custom `analyze`** (for closure state, pre-/post-phases):

```crystal
class MyFramework < JavascriptEngine
  def analyze
    result = [] of Endpoint
    static_dirs = [] of Hash(String, String)

    parallel_file_scan do |path|
      # ... build endpoints into result, collect static_dirs
    end

    process_static_dirs(static_dirs, result)  # post-pass
    result
  end
end
```

Used when the analyzer needs local state during the scan (mutexes, dedup sets) or a post-processing pass. Express, Hono, Rails, and Amber are examples.

## Detector shape

Detectors are almost always a one-line match:

```crystal
# src/detector/detectors/go/hertz.cr
module Detector::Go
  class Hertz < Detector
    detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]

    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end
  end
end
```

`detector_for` declares the tech name once and generates the cheap file gate (`applicable?`) that decides which files `detect` is even offered. The gate keys are `extensions:`, `basenames:` and `path_segments:`; a detector whose `detect` has side effects — registering spec paths in `CodeLocator`, say — must also pass `idempotent: false` so the pass keeps calling it after its first match.

The detector runs once per candidate file in the project. Returning `true` marks the framework as present and tells the pipeline to run the matching analyzer.

## Adding a new framework

Walkthrough using **Hertz (Go)** as the concrete example. Real PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

Create `src/detector/detectors/{language}/{framework}.cr`:

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

### 2. Analyzer

Create `src/analyzer/analyzers/{language}/{framework}.cr`. Inherit from the language engine. For Hertz (Gin-like), much of the structure is shared with Gin:

```crystal
require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    analyzer_for "go_hertz"

    HTTP_METHODS_EXPANDED = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    def analyze
      public_dirs = [] of Hash(String, String)
      package_groups, file_lines_cache = collect_package_groups

      parallel_file_scan do |path|
        lines = file_lines_cache[path]? || File.read_lines(path, encoding: "utf-8", invalid: :skip)
        groups = groups_for_directory(package_groups, File.dirname(path))
        # ... per-line route + param extraction, delegates to GoRouteExtractor via engine
      end

      resolve_public_dirs(public_dirs)
      result
    end
  end
end
```

Key points:

- **Inherit from the language engine** (`GoEngine` here). You get `get_route_path`, `add_param_to_endpoint`, `collect_package_groups`, `resolve_public_dirs` for free.
- **Declare the tech with `analyzer_for`**. That single line *is* the registration — see step 3.
- **Override overridable methods** if your framework's parsing differs (`get_static_path`, `get_route_path`; see Mux or GoZero for examples).
- **Use `parallel_file_scan`** for the file walk; don't re-implement the channel + worker pool.

### 3. Declare the tech metadata

There is **no registration list to edit**. The analyzer and detector registries are derived from the classes themselves: `initialize_analyzers` (`src/analyzer/analyzer.cr`) and `build_detector_list` (`src/detector/detector.cr`) each sweep `all_subclasses` and read the name off `analyzer_for` / `detector_for`. Both lists used to be hand-maintained, and forgetting an entry produced no error and no failing spec — just a component that silently never ran.

So the only thing left to add is the catalog entry — a new file, at the same relative path as the analyzer and the detector:

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
      :context => { :callee => true },
    },
  }
end
```

`spec/unit_test/techs/registry_integrity_spec.cr` asserts the three-way linkage in both directions: every analyzer and detector has a catalog entry, and every catalog entry is backed by both. A missing catalog entry fails there rather than at runtime.

### 4. Fixture

Create `spec/functional_test/fixtures/{language}/{framework}/` with a minimal app:

```
spec/functional_test/fixtures/go/hertz/
├── go.mod            # import line the detector will match
├── main.go           # exercise every route/param pattern you care about
└── public/           # optional: for static-file detection
    └── index.html
```

The fixture should exercise realistic patterns: path params, query/form/header/cookie, route groups, static serving, and any framework-specific idioms (Hertz's `.Any` expands to all HTTP methods, Flask's blueprints, etc.). Don't try to be exhaustive; add cases as real-world bugs surface.

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

The tester asserts:
- The detector finds exactly 1 tech (your framework).
- The analyzer produces exactly N endpoints (matches `expected_endpoints.size`).
- For each expected endpoint, an endpoint with matching URL + method exists in the output.
- For each expected param, a matching `name + param_type` is attached to that endpoint.

### 6. Verify

```bash
just build                 # compiles cleanly
just test                  # unit + functional spec pass
just check                 # crystal tool format --check + ameba

# Manual smoke test
./bin/noir -b spec/functional_test/fixtures/{lang}/{framework}
```

## Adding a new language engine

When a language has 2+ analyzers that share a file-walk pattern, extract an engine. **Inherit from `FileScanEngine`** — it already owns the walk. Your engine declares only what is language-specific: which files to scan, which to skip, and any shared route-composition helpers.

```crystal
# src/analyzer/engines/swift_engine.cr
require "../../models/analyzer"

require "./file_scan_engine"

module Analyzer::Swift
  abstract class SwiftEngine < FileScanEngine
    # Candidate files. Prefer the detector-built extension index over
    # walking the whole `file_map` — these are registered regular files,
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

`FileScanEngine` supplies `analyze` (walk, call `analyze_file` per path, concat), the `abstract def analyze_file(path) : Array(Endpoint)` contract, and `parallel_file_scan` for subclasses that need a custom `analyze` shape. Do not re-implement the channel + worker pool: nine engines each carried a byte-identical copy of it before [#2465](https://github.com/owasp-noir/noir/pull/2465) hoisted it, and a hand-rolled copy re-opens that duplication.

When adding the engine, migrate existing analyzers to inherit from it in the same PR. See [#1236](https://github.com/owasp-noir/noir/pull/1236) (Elixir), [#1237](https://github.com/owasp-noir/noir/pull/1237) (Swift), [#1238](https://github.com/owasp-noir/noir/pull/1238) (Crystal) for worked examples.

## Adding a route extractor (L1)

When 2+ analyzers in a language share real parsing logic (not just file walking), extract a route extractor module under `src/miniparsers/{lang}_route_extractor.cr`. Pure functions, no `Analyzer` dependency:

```crystal
module Noir::MyLangRouteExtractor
  extend self

  def extract_route_path(line : String, groups : Array(...)) : String
    # pure parsing
  end
end
```

The engine then exposes thin instance-method delegations so adapter subclasses can override if their framework parses differently:

```crystal
class MyLangEngine < Analyzer
  def get_route_path(line, groups)
    Noir::MyLangRouteExtractor.extract_route_path(line, groups)
  end
end
```

See [#1243](https://github.com/owasp-noir/noir/pull/1243) (Go `common.cr` split) for the canonical example. Once an extractor outgrows one file, split it into a directory of part files behind an umbrella `require` rather than letting it grow — [`go_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/go_route_extractor_ts) is split by framework family, [`kotlin_route_extractor_ts/`](https://github.com/owasp-noir/noir/tree/main/src/miniparsers/kotlin_route_extractor_ts) by concern.

## Execution model note

Noir is built **single-threaded** (no `preview_mt`). `parallel_analyze` spawns cooperative Crystal fibers, not OS threads, so `result << endpoint` and `result.concat(...)` from multiple fibers are safe because `Array#<<` and `#concat` have no yield points. You'll notice that no per-file analyzer uses a `Mutex` around the result array; that's by design and matches the whole codebase. If noir ever enables MT mode, synchronization belongs at the `parallel_analyze` layer, not scattered across analyzers.

A `@result_mutex` plus `append_endpoint` helpers were added to the engines in #2353 and removed again in #2357: they guarded a race that cannot occur in a single-threaded build, landed in only some engines, and contradicted this note. If you are about to add one, you are re-opening that loop — enable MT first, then synchronize once at the `parallel_analyze` layer.

## Where to look next

- Reference analyzer: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- Shared file-walk base: [`engines/file_scan_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/file_scan_engine.cr)
- Reference engine + extractor pair: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor_ts.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor_ts.cr)
- Custom-shape example: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (pre-phase + closure state)
- Framework-adapter-only example: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (first framework added after the engine refactor)
