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

Every analyzer is composed of three layers. Keeping them separate is a hard rule — a framework adapter should not open files or re-implement parsing.

| Layer | Lives in | Responsibility |
|---|---|---|
| **L0 Language Engine** | `src/analyzer/engines/{lang}_engine.cr` | File walking, concurrency (`parallel_analyze`), channel setup, per-path error handling. One per language. |
| **L1 Route Extractor** | `src/miniparsers/{lang}_route_extractor.cr` | Parses source content. Takes a string (file contents), yields route declarations (method, path, location). No file I/O, no framework-specific rules. |
| **L2 Framework Adapter** | `src/analyzer/analyzers/{lang}/{framework}.cr` | Thin per-framework class. Consumes routes from the extractor and applies framework-specific param mappings, filters, and special cases. |

**Reference implementation**: [`src/analyzer/analyzers/javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr) on top of [`src/miniparsers/js_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/js_route_extractor.cr). Hono is ~205 lines because it follows the split; contrast with analyzers that inline all three responsibilities and grow to 500–800 lines.

## Current coverage

- **Language engines** (in `engines/`): PHP, Ruby, Rust, Elixir, Swift, Crystal, Scala, JavaScript/TypeScript, Python, Go.
- **Route extractors** (in `miniparsers/`): JavaScript (used by Hono, Express, Fastify, Koa, NestJS, Restify, TypeScript NestJS) and Go (used by eight analyzers).
- **Deliberately outside the engine stack**: CSharp's two orchestrators and Scala Play (multi-phase flows that don't fit a per-file scan), plus Go's Chi/Httprouter/Fasthttp (self-contained extraction). These inherit from `Analyzer` directly.
- Python, Kotlin, Java have full parsers (in `miniparsers/`) but no dedicated route extractor yet — it's a known follow-up.

## Two engine shapes

Every engine exposes `parallel_file_scan(&block)` as a protected helper. A framework adapter picks one of two shapes:

**Shape A — `analyze_file`** (simpler, pure per-file):

```crystal
class MyFramework < PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    return [] of Endpoint unless path.ends_with?(".php")
    # parse, build endpoints, return them
  end
end
```

The engine's default `analyze` drives the walk and concats returned endpoints. Used by most Php / Rust / Swift / Crystal / Elixir / Scala analyzers.

**Shape B — custom `analyze`** (for closure state, pre-/post-phases):

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
    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end

    def set_name
      @name = "go_hertz"
    end
  end
end
```

The detector runs once per candidate file in the project. Returning `true` marks the framework as present and tells the pipeline to run the matching analyzer.

## Adding a new framework

Walkthrough using **Hertz (Go)** as the concrete example. Real PR: [#1244](https://github.com/owasp-noir/noir/pull/1244).

### 1. Detector

Create `src/detector/detectors/{language}/{framework}.cr`:

```crystal
require "../../../models/detector"

module Detector::Go
  class Hertz < Detector
    def detect(filename : String, file_contents : String) : Bool
      filename.includes?("go.mod") && file_contents.includes?("github.com/cloudwego/hertz")
    end

    def set_name
      @name = "go_hertz"
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
- **Override overridable methods** if your framework's parsing differs (`get_static_path`, `get_route_path` — see Mux or GoZero for examples).
- **Use `parallel_file_scan`** for the file walk; don't re-implement the channel + worker pool.

### 3. Register in three places

```crystal
# src/analyzer/analyzer.cr
{"go_hertz", Go::Hertz},

# src/detector/detector.cr
Go::Hertz,

# src/techs/techs.cr
:go_hertz => {
  :framework => "Hertz",
  :language  => "Go",
  :similar   => ["hertz", "go-hertz", "cloudwego"],
  :supported => {
    :endpoint => true,
    :method   => true,
    :params   => { :query => true, :path => true, :body => true, :header => true, :cookie => true },
  },
},
```

### 4. Fixture

Create `spec/functional_test/fixtures/{language}/{framework}/` with a minimal app:

```
spec/functional_test/fixtures/go/hertz/
├── go.mod            # import line the detector will match
├── main.go           # exercise every route/param pattern you care about
└── public/           # optional: for static-file detection
    └── index.html
```

The fixture should exercise realistic patterns: path params, query/form/header/cookie, route groups, static serving, and any framework-specific idioms (Hertz's `.Any` expands to all HTTP methods, Flask's blueprints, etc.). Don't try to be exhaustive — add cases as real-world bugs surface.

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
crystal tool format --check
crystal run lib/ameba/bin/ameba.cr

# Manual smoke test
./bin/noir -b spec/functional_test/fixtures/{lang}/{framework}
```

## Adding a new language engine

When a language has 2+ analyzers that share a file-walk pattern, extract an engine. Template, using `SwiftEngine` as the model:

```crystal
# src/analyzer/engines/swift_engine.cr
require "../../models/analyzer"

module Analyzer::Swift
  abstract class SwiftEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)
        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".swift"

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end
  end
end
```

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

See [#1243](https://github.com/owasp-noir/noir/pull/1243) (Go `common.cr` split) for the canonical example.

## Execution model note

Noir is built **single-threaded** (no `preview_mt`). `parallel_analyze` spawns cooperative Crystal fibers, not OS threads — so `result << endpoint` and `result.concat(...)` from multiple fibers are safe because `Array#<<` and `#concat` have no yield points. You'll notice that no per-file analyzer uses a `Mutex` around the result array; that's by design and matches the whole codebase. If noir ever enables MT mode, synchronization belongs at the `parallel_analyze` layer, not scattered across analyzers.

## Where to look next

- Reference analyzer: [`javascript/hono.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/hono.cr)
- Reference engine + extractor pair: [`engines/go_engine.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/engines/go_engine.cr) + [`miniparsers/go_route_extractor.cr`](https://github.com/owasp-noir/noir/blob/main/src/miniparsers/go_route_extractor.cr)
- Custom-shape example: [`javascript/express.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/javascript/express.cr) (pre-phase + closure state)
- Framework-adapter-only example: [`go/hertz.cr`](https://github.com/owasp-noir/noir/blob/main/src/analyzer/analyzers/go/hertz.cr) (first framework added after the engine refactor)
