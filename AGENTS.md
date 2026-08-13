# OWASP Noir - Attack Surface Detector

Crystal-based attack surface detector that identifies endpoints by static analysis of source code across multiple languages and frameworks.

**Reference these instructions first. Fallback to search or bash only when information here is outdated.**

## Build and Test

**NEVER CANCEL builds or tests. Always use appropriate timeouts.**

| Command | Alternative | Timeout |
|---------|-------------|---------|
| `just build` | `shards build` | 120s (~30s typical) |
| `just test` | `crystal spec` | 60s (~10s typical) |
| `just check` | format check + lint | 60s |
| `just fix` | auto-format + fix lint | 60s |

```bash
# Docker build (for CI or consistent environments)
docker run --rm -v $(pwd):/app -w /app crystallang/crystal:1.21.0-alpine sh -c "apk add --no-cache yaml-dev zstd-dev && shards install && shards build"

# Local install (Ubuntu/Debian)
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt install -y just
```

## Usage

```bash
./bin/noir -h                                           # Help (includes all output formats)
./bin/noir list techs                                   # List all supported technologies
./bin/noir list taggers                                 # List available taggers
./bin/noir -b path/to/source                            # Basic analysis
./bin/noir -b . -f json                                 # JSON output (see -h for all formats)
./bin/noir -b . --verbose                               # Detailed analysis
./bin/noir -b . -P                                      # Passive security scan
./bin/noir -b . --probe-via http://127.0.0.1:8080      # Forward to proxy (Burp/ZAP)
./bin/noir -b . --ai-provider openai --ai-model gpt-4  # AI-powered analysis
```

## Repository Structure

```
src/
├── analyzer/analyzers/     # Endpoint/parameter analyzers by language/framework
├── analyzer/engines/       # Shared per-language bases (see Analyzer Layering)
├── detector/detectors/     # Technology detection by language/framework
├── cli/                    # Subcommand router and commands (scan, list, config, …)
├── ext/                    # External C/C++ bindings (e.g., Tree-sitter integration)
├── output_builder/         # Output format generation (JSON, YAML, OAS, etc.)
├── models/                 # Base classes + data structures (includes minilexer/)
├── llm/                    # AI/LLM integration (general/, ollama/, acp/)
├── ai_context/             # AI review-context assembly
├── mobile/                 # Mobile deep-link linking (Android/iOS)
├── optimizer/              # Endpoint normalization/dedup and LLM optimizer
├── tagger/taggers/         # Endpoint tagging implementations
├── tagger/framework_taggers/ # Framework-specific auth taggers (by language)
├── deliver/                # Results delivery (proxy, elasticsearch)
├── minilexers/             # Custom lexers
├── miniparsers/            # Custom parsers
├── passive_scan/           # Passive security scanning
├── techs/catalog/{lang}/   # Technology metadata, one file per technology
├── utils/                  # Utility functions
├── noir.cr                 # Main entry point
├── options.cr              # CLI options parser
├── config_initializer.cr   # Configuration initialization
├── completions.cr          # Shell completion generation
└── banner.cr               # Banner display

spec/
├── functional_test/
│   ├── fixtures/           # Sample code for testing (by language/framework)
│   └── testers/            # Functional test implementations
└── unit_test/              # Unit tests (mirrors src/ structure)
```

### Key Files
- `shard.yml` - Dependencies and project metadata
- `justfile` - Task definitions (`just --list` for all commands)
- `.ameba.yml` - Linting configuration
- `.github/workflows/ci.yml` - CI configuration

## Analyzer Layering

An analyzer is composed of three layers. Keep them separate — a framework adapter should not open files or re-implement parsing.

1. **Language Engine** — shared per-language base in `src/analyzer/engines/{lang}_engine.cr`. Owns file walking, concurrency, worker pool, file-content caching.
2. **Route Extractor** — shared per-language parser layer (`src/miniparsers/{lang}_route_extractor.cr`). Takes source content, yields route declarations (method, path, location). No file I/O, no framework-specific rules.
3. **Framework Adapter** — thin per-framework class (`src/analyzer/analyzers/{lang}/{framework}.cr`). Consumes routes from the extractor and applies framework-specific param mappings, filters, and special cases.

**Rule**: the framework adapter receives routes; it does not walk the filesystem or parse tokens itself.

`spec/unit_test/analyzer/layering_boundary_spec.cr` enforces the file-walking half of that rule: `Dir.glob` / `Dir.children` / `Dir.each_child` under `src/analyzer/analyzers/**` fails the suite. Get your file set from your language's engine (whichever walk helper it exposes — see **Engine walk vocabularies** below; they are not uniform) or from a detector-built index (`get_files_by_extension`, `CodeLocator#files_by_basename`) — walking a directory yourself bypasses subtree pruning, `--exclude-path`, the media filter and the content cache. The spec carries an allowlist of the six adapters that still walk; it is a ratchet, so entries may be removed but never added. It also forbids shadowing `Analyzer#read_file_content` or hand-rolling its `content_for(path) || TextFile.read(path)` body.

**Reference implementations — no single analyzer is the whole model yet.** Cite each for the layer it actually demonstrates:

- **Getting your file set (L0)**: `src/analyzer/analyzers/javascript/hono.cr` — inherits `JavascriptEngine` and drives the walk with `parallel_file_scan`, so it gets the worker pool, the content cache and the language's test/vendor filters for free. `src/analyzer/engines/file_scan_engine.cr` (34 lines) is the exemplary shared layer itself.
- **Delegating the parse and staying thin (L1→L2)**: `src/analyzer/analyzers/javascript/hapi.cr` — 54 lines, 3 methods, no tokenizing at all. It calls `Noir::TreeSitterHapiExtractor.extract_routes` and does nothing but map the result onto `Param`s. Same shape: `javascript/elysia.cr` (54), `javascript/adonisjs.cr` (62), `kotlin/http4k.cr` (91), `java/spark.cr` (129).

Each is also a counter-example on the other axis, and knowing which way is what keeps you from copying the wrong half:

- `hono.cr` is right on L0 and **wrong on L2**. Only ~40 of its 385 lines are extractor delegation; the rest is layers 2 and 3 fused — a char-by-char `split_top_level_args` (one of many private re-implementations: `grep -rn 'def \(self\.\)\?split_top_level_args' src/` lists them all, and every hit outside the canonical `src/miniparsers/js_http_route_extractor.cr` is a framework adapter carrying its own copy), `skip_whitespace`, `line_for_pos`, a second independent regex line-walk for `app.on(...)`, full inline route/param regex tables, and the HTTP verb list declared twice in one file (L75 and L333). Its own comment admits it: *"this auxiliary pass has its own regex walk, so it has to repeat the same gates"*.
- `hapi.cr` and the other thin adapters are right on L2 and **wrong on L0**: they extend `Analyzer` directly and re-walk `all_files()` themselves with a `File.exists?` guard that is redundant on detector-registered paths. They should ride their language engine.

So: take the walk from `hono.cr`, take the body from `hapi.cr`, and write the analyzer neither of them is yet.

**Current coverage**:
- Language engines (`src/analyzer/engines/`, **direct** subclass count in parentheses — re-derive any of them with `grep -rc "< {Engine}" src/`; transitive inheritors are deliberately *not* counted, so `Bandit < Plug < ElixirEngine` contributes only `Plug` to `ElixirEngine`'s 2): `SpecificationEngine` (45), `JavascriptEngine` (18), `GoEngine` (16), `PythonEngine` (16), `PhpEngine` (15), `RustEngine` (10), `RubyEngine` (8), `CrystalEngine` (6), `CfmlEngine` (5), `ScalaEngine` (5), `SwiftEngine` (3), `PerlEngine` (3), `ElixirEngine` (2). `java_engine.cr` and `kotlin_engine.cr` are **not** engines — they are modules exposing a shared `self.test_path?` and nothing inherits from them.
- `FileScanEngine` (`src/analyzer/engines/file_scan_engine.cr`) is the shared base *under* seven of those engines (Crystal, Elixir, Perl, Php, Rust, Scala, Swift). It owns the `analyze` + `parallel_file_scan` skeleton those engines used to each carry a copy of.
- `CliEndpointSupport` (`src/analyzer/engines/cli_endpoint_support.cr`) is a **mixin**, not a base: it holds the `fetch_endpoint` that all 21 `analyzers/{lang}/cli.cr` files carried an identical copy of. Those 21 have no common base below `Analyzer` — 17 extend `Analyzer` directly and Go/JavaScript/Python/Ruby extend their language engine — so shared CLI behaviour has to be `include`d. Their *other* look-alike helpers (`cli_test_path?`, `cli_binary_name`, `cli_evidence?`) are deliberately **not** here: each reads a per-class constant whose value differs by language, so they are textually identical while resolving to different regexes.
- Languages with no engine — including CSharp, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua and Groovy — extend the `Analyzer` base directly: their flows orchestrate multiple phases or carry self-contained extraction that doesn't share with other analyzers.
- Route extractors:
  - JavaScript/TypeScript: `js_route_extractor.cr`. Express, Fastify, Hono, Koa and Restify drive their routes through `JSRouteExtractor.extract_routes`; NestJS, Next.js, Nuxt, Fresh, Apollo, tRPC and TanStack Router pull only its helpers (`find_matching_paren`, `strip_js_comments`, `test_stub_only?`, …). AdonisJS, Elysia and Hapi do **not** get routes from it — they have their own AST extractors (see below); AdonisJS borrows just the `test_stub_only?` gate.
  - High-fidelity Tree-sitter-based extractors (`*_route_extractor_ts.cr` and `*_parameter_extractor_ts.cr`) utilising vendored libtree-sitter bindings. The Go and Kotlin ones are **directories** of part files behind an umbrella `require`, not single files:
    - Go: `go_route_extractor_ts.cr` + `go_route_extractor_ts/`
    - Java: `java_route_extractor_ts.cr`, `java_parameter_extractor_ts.cr` (used by Spring, JAX-RS, Micronaut, etc.)
    - Kotlin: `kotlin_route_extractor_ts.cr` + `kotlin_route_extractor_ts/`, `kotlin_ktor_route_extractor_ts.cr`, `kotlin_parameter_extractor_ts.cr` (used by Spring, Ktor, etc.)
    - Python: `python_route_extractor_ts.cr` (`Noir::TreeSitterPythonRouteExtractor`, used by aiohttp, Bottle, Flask, Quart, Robyn and Sanic — those six also require the line-level `python_route_extractor.cr` alongside it). FastAPI and Django use **neither** miniparser: both are self-contained `PythonEngine` subclasses that do their own decorator/URLconf walk.
    - Framework-specific AST extractors: `adonisjs_extractor_ts.cr`, `elysia_extractor_ts.cr`, `hapi_extractor_ts.cr`, `http4k_extractor_ts.cr`, `jaxrs_extractor_ts.cr`, `micronaut_extractor_ts.cr`, `jvm_lambda_dsl_extractor_ts.cr`
  - Traditional / Callee Extractors: Used as a fallback or framework-specific extraction across languages (e.g., `cpp_callee_extractor.cr`, `crystal_callee_extractor.cr`, `go_callee_extractor.cr`, `js_callee_extractor.cr`, `ruby_callee_extractor.cr`, etc.).

When adding a new framework in a language that already has an extractor, extend the extractor rather than re-parsing inline.

**Engine walk vocabularies** — there is no single walk API shared by all engines. `parallel_file_scan(&block)` is defined in exactly three files (`grep -rln "def parallel_file_scan" src/analyzer/engines/`): `file_scan_engine.cr`, `javascript_engine.cr` and `ruby_engine.cr`. Before writing an adapter, check which vocabulary *your* language's engine offers:

- **`FileScanEngine` shape** (`ElixirEngine`, `CrystalEngine`, `PerlEngine`, `PhpEngine`, `RustEngine`, `ScalaEngine`, `SwiftEngine`): the engine supplies the candidate list via `scan_target_files` and an optional per-path veto via `scan_accepts?`; the adapter overrides `abstract def analyze_file(path) : Array(Endpoint)` and `FileScanEngine#analyze` drives the walk and concats the results. Adapters that need closure state, a pre-phase or post-processing (Amber/Kemal's public-dir pass) override `analyze` and call the inherited `parallel_file_scan` directly.
- **Own `parallel_file_scan`** (`JavascriptEngine`, `RubyEngine`): same helper name, but these engines define it themselves and have no `scan_target_files`. Adapters override `analyze` and call `parallel_file_scan`, which is what lets Express run `scan_for_router_mounts` first and Hono run `process_static_dirs` after.
- **Language-specific iterators**: `PythonEngine` offers `python_source_files` / `each_python_source` / `parallel_python_sources`; `SpecificationEngine` offers `each_spec_file` / `each_spec_file_with_details`, driven by `CodeLocator` spec-path keys rather than a directory walk; `CfmlEngine` offers `cfml_components` / `cfml_pages`; `GoEngine` hands the adapter whole-package content via `read_package_file_contents` plus the `collect_*` helpers. None of these four define `parallel_file_scan` or `scan_target_files`.
- **No engine at all** (CSharp, Java, Kotlin, Dart, Zig, C++, Clojure, Haskell, Lua, Groovy): the adapter extends `Analyzer` and uses `scan_files(files, &block)` — the shared skeleton on the base that every one of the above ultimately funnels into.

## Adding New Components

**There are no registration lists to edit.** Analyzers, detectors and output formats each join their registry by declaring their own name on the class; the registry is derived from the classes by macro. Adding a name to a hand-maintained list used to be a second place to remember, where forgetting produced no error and no failing spec — just a component that never ran.

### Analyzers
1. Create `src/analyzer/analyzers/{language}/{framework}.cr` — framework adapter only. Delegate parsing to the language's route extractor (see **Analyzer Layering** above).
2. Declare the tech inside the class: `analyzer_for "{language}_{framework}"`. This is the whole registration (`src/models/analyzer.cr`); `initialize_analyzers` reads it off `Analyzer.all_subclasses`. Omitting it is a compile error.
3. Add functional test: `spec/functional_test/testers/{language}/{framework}_spec.cr`
4. Add fixtures: `spec/functional_test/fixtures/{language}/{framework}/`
5. Add technology metadata: create `src/techs/catalog/{language}/{framework}.cr` (mirrors the analyzer's path)

### Detectors
1. Create `src/detector/detectors/{language}/{framework}.cr`
2. Declare the tech and its file gate inside the class: `detector_for "go_hertz", extensions: %w[.go], path_segments: %w[go.mod]` (`src/models/detector.cr`). The gate keys are `extensions:`, `basenames:` and `path_segments:`; pass `idempotent: false` only if `detect` has side effects, such as registering paths in `CodeLocator`.
3. Add unit test: `spec/unit_test/detector/{language}/{framework}_spec.cr` — required; `spec/unit_test/techs/detector_coverage_spec.cr` fails without it
4. Add technology metadata: create `src/techs/catalog/{language}/{framework}.cr` (mirrors the detector's path)

### Output Formats
1. Create `src/output_builder/{format}.cr` (no `_builder` suffix)
2. Annotate the class: `@[Noir::OutputFormat(name: "{format}", description: "…", order: 40)]`. `src/output_builder/formats.cr` derives the catalog, the `-f` help text and the render dispatch from the annotation — `src/options.cr` needs no edit.
3. Add unit test: `spec/unit_test/output_builder/{format}_spec.cr`

### Taggers
1. Create `src/tagger/taggers/{tagger_name}.cr`
2. Annotate the class: `@[Noir::TaggerFor(key: "{tagger_name}", name: "{Name} Tagger", desc: "…", order: 180)]`. This is the whole registration — `src/tagger/tagger.cr` derives the registry, the `-T` key, the `noir list taggers` entry and the run dispatch from the annotation. Unlike `analyzer_for`, omitting it is *not* a compile error; `spec/unit_test/techs/registry_integrity_spec.cr` fails and names the class.
3. `key` is also the tagger's runtime `name` — `Tagger#initialize` reads it back off the annotation, so do not assign `@name` yourself. `order` fixes the sequence plain taggers run in, which is user-visible: they run sequentially, `Endpoint#add_tag` appends, and nothing sorts tags before output. Values are spaced by 10, so append rather than renumber.
4. Add unit test: `spec/unit_test/tagger/{tagger_name}_spec.cr`

### Framework Taggers (Auth Taggers)
Framework taggers detect framework-specific patterns (e.g., auth decorators, middleware, guards) and tag endpoints accordingly. They extend `FrameworkTagger < Tagger` which provides file caching and `read_source_context()`.

1. Create `src/tagger/framework_taggers/{language}/{tagger_name}.cr`
   - Inherit from `FrameworkTagger`
   - Override `self.target_techs` to return matching technology strings (e.g., `["python_django"]`)
   - Override `perform(endpoints)` to check and tag endpoints
   - Use `read_file(path)` (cached) and `read_source_context(endpoint)` helpers
2. Annotate the class: `@[Noir::TaggerFor(key: "{tagger_name}", name: "{Framework} Auth Tagger", desc: "…", order: 270)]` — same annotation and same rules as plain taggers above. Framework taggers run under a `WaitGroup`, so for them `order` only sequences `noir list taggers`.
3. Add unit test: `spec/unit_test/tagger/framework_taggers/{tagger_name}_spec.cr`
4. Add fixtures: `spec/functional_test/fixtures/{language}/{framework}_auth/`

Key design notes:
- `FrameworkTagger` inherits from `Tagger` — shares `@logger`, `@options`, `@name`, `perform()` interface
- `@file_cache` prevents redundant reads within a tagger run (pre-scan + per-endpoint checks)
- Framework taggers are dispatched only when endpoints matching their `target_techs` exist
- Scope tracking (Go groups, Ktor authenticate blocks, Express app.use) uses heuristic brace counting — not AST-level, so edge cases with braces in strings/comments may occur

**After any new component: run `just test` to validate.**

## Before Committing

1. `just build` - Ensure compilation succeeds
2. `just test` - Ensure all tests pass
3. `crystal tool format` - Format code
4. Verify basic functionality: `./bin/noir -b spec/functional_test/fixtures/crystal`

## Environment
- Crystal ~> 1.19 (CI: 1.21.0)
- Docker image: `crystallang/crystal:1.21.0-alpine`
- Dependencies: `libyaml-dev`, `libzstd-dev`, `zlib1g-dev`, `pkg-config`
