# Changelog

All notable changes to [Noir](https://github.com/owasp-noir/noir) will be documented in this file.

## v1.1.0

Noir v1.1.0 is a large coverage and accuracy release. It introduces mobile deep-link analysis, Zig support, and a broad set of new framework, tagger, and specification analyzers, alongside a codebase-wide accuracy sweep and significant performance work.

### Added
- **Mobile analyzer**: Android (manifest) and iOS (Info.plist/entitlements) deep-link entry points, linked to handler code with callees, input params, and AI context. Includes universal links (assetlinks.json / AASA), Jetpack Navigation graphs, exported components (explicit-intent surfaces), and ContentProviders (`content://` IPC).
- **Zig support**: Jetzig, Zap, httpz, and Tokamak framework analyzers.
- New framework analyzers:
  - C++: oat++, cpp-httplib
  - Go: go-restful
  - Lua: lor (OpenResty)
  - Dart: GetServer, Alfred, Angel3
  - PHP: Mautic, Laminas, ThinkPHP
  - Perl: Catalyst, Dancer2
  - Clojure: Pedestal
  - Java: Apache Wicket, Apache Struts 2
  - C#: ASP.NET Core Minimal API
- New specification analyzers: Kamal (`deploy.yml`), Apache httpd, nginx, and Kubernetes Ingress.
- OAS2/OAS3 security-scheme parameter extraction (API key, OAuth2, and HTTP auth schemes emitted as endpoint parameters).
- New endpoint taggers: `pii`, `admin`, `payment`, `webhook`, `crypto`, `debug`, `api_docs`, and `account_recovery`.
- New framework security taggers for Rails, Spring, Go, and Rust (CSRF, CORS, rate-limit, security-headers, and more).
- `-f adb` and `-f simctl` output formats to launch Android and iOS mobile entry points directly.
- Structural miniparsers for PHP (`PhpLexer`), C# (`CSharpLexer`), and Scala (`ScalaLexer`) to cut false positives/negatives in code/string-aware scanning.
- Added `claude-opus-4-8`, `claude-fable-5`, `claude-mythos-5`, and `grok-build-0.1` to the AI provider token map.

### Changed
- Redesigned the HTML report (`-f html`) as a self-contained monochrome theme with light/dark toggle, collapsible cards, and search/method/severity filters.
- Refactored the AI-context augmentor monolith into focused modules.

### Performance
- Eliminated PCRE2/interpolated-regex recompilation across Python, JS/TS, JVM, Scala, C++, Ruby, Go, Elixir, and security-tagger analyzers, yielding large speedups on big projects (e.g. Elixir/Blockscout 32s → 1.7s).
- Improved monorepo multi-base-path scanning (path-boundary scoping and cache-first reads).
- Reduced per-file work in the PHP, Kotlin/Spring, and Python analyzers.
- Removed quadratic (O(n²)) scans in the GraphQL SDL detector and type-definition extractor.

### Analyzer Accuracy
- Codebase-wide FP/FN, parameter, and callee accuracy sweep validated against real OSS applications across nearly every supported language: Java/Kotlin (Spring, Armeria, Play, Spark, JSP, Struts), JavaScript/TypeScript (Express, Hono, NestJS, Next.js, Koa, tRPC, TanStack Router, SvelteKit, Remix, and more), Python (Flask, FastAPI, Django, Tornado, Pyramid, Starlette, Sanic, Litestar), Ruby (Rails, Sinatra, Grape, Hanami, Roda), PHP (Laravel, CakePHP, Symfony, Laminas), Go (Gin, Echo, Chi, mux, GoFrame, go-zero, PocketBase), Rust (Actix, Axum, Warp, Salvo, Poem, Rocket, Loco, RWF, Gotham, Tide), Swift (Vapor, Hummingbird, Kitura), Scala (Play, Akka, http4s, tapir, ZIO HTTP, Scalatra), Dart, Crystal, Clojure, Lua, Perl, Haskell, F#, C++, and C#.
- Standardized prefix composition (nested groups, scopes, mounts, and cross-file/cross-function route registration) across many frameworks.
- Improved tagger precision/recall, including `oauth`, `webhook`, `account_recovery`, `api_docs`, and `debug`.
- Improved specification-format coverage and precision across OAS/Swagger, GraphQL SDL (operation documents and `.gql`), RAML (`uses:` libraries, non-API fragment skipping, optional/pattern params, annotated `baseUri`), WSDL (`wsdl:import` split definitions, RPC scalar message parts), gRPC (cross-import and fully-qualified request messages, `additional_bindings` and custom-verb HTTP transcoding), and Postman/Insomnia (auth schemes and raw-string bodies).

### Fixed
- Hardened source scanning against a crash and several O(n²) DoS hangs on large or adversarial inputs.
- Fixed a wide class of byte-vs-char index bugs causing crashes, callee corruption, and wrong line numbers across the Rust, Java, Python, PHP, Go, C++, Dart, Clojure, Haskell, and Ruby analyzers.
- Fixed header truncation, `.http` rewrite, fiber leak, config probe coercion, OpenRouter limit, and TOML/diff/Postman output edge cases.
- Reduced passive-scan secret false positives — suppressed matches on variable names merely referenced in comments, prose, or dependency lists; env-helper reads (`env('X')`, `process.env`); CI and shell interpolation; empty values; and documentation placeholders (`your-access-key`, `<token>`).
- Hardened specification parsing against silently dropped documents — recover OAS specs that libyaml rejects over stray tabs, ignore commented-out gRPC declarations, and require a real `service` block in the gRPC detector to cut false-positive detections.

## v1.0.0

Noir v1.0.0 introduces a stable 1.x release line across all analyzers, taggers, and passive-scan features. The CLI transitions to a verb-centric command structure (`scan`, `list`, `cache`, `config`, `rules`, `completion`, `version`, `help`) while preserving complete backward compatibility with v0 flags and syntax (e.g., `noir -b ./app`). For details, see the [CLI commands reference](docs/content/usage/cli_commands/_index.md).

### Added
- Verb-based CLI structure:
  - `noir scan PATHS...` — Run endpoint scanning with positional paths.
  - `noir list techs|taggers|formats` — List built-in catalogs.
  - `noir cache info|clear|purge` — Manage on-disk LLM response cache.
  - `noir config show|edit|init|path` — Manage user-level YAML configuration.
  - `noir rules list|update|path` — Manage passive-scan rules.
  - `noir completion <shell>` — Generate shell completion script (Zsh, Bash, Fish, Elvish).
  - `noir version [--verbose]` — Show version and build details.
  - `noir help [command]` — Show command-specific help documentation.
- `--pvalue TYPE=VAL` (repeatable) flag to specify parameter values by type (`any`, `header`, `cookie`, `query`, `form`, `json`, `path`).
- `--include LIST` flag for comma-separated enrichment toggles (`path`, `techs`, `callee`).
- `--ai-context[=LIST]` flag to filter emitted AI-context categories (`guards`, `sinks`, `validators`, `signals`, `callee`).
- `--no-color` flag (and `NO_COLOR` env var) support across all subcommands.
- Elvish shell completion support.
- JSON output fields `callees` (1-hop call graph) and `ai_context` (per-endpoint AI context when enabled).
- Bundled `noir-passive-rules` snapshot in the Docker image at `/opt/noir/passive_rules/` for offline `-P` scanning out-of-the-box.

### Changed
- Bare-flag invocations are automatically routed to the `scan` subcommand, maintaining full compatibility with v0 scripts.
- Legacy flags are silently rewritten to their v1 equivalents (e.g., `--list-techs` → `noir list techs`, `--build-info` → `noir version --verbose`).
- Shell completions are now fully aware of subcommands and scan-specific flags.
- Default scanning concurrency now scales dynamically based on CPU core count (`System.cpu_count.clamp(4, 32)`).
- GitHub Action migrated to `composite` action using pre-built Docker images, significantly reducing execution startup time.
- Docker image is now fully self-contained, folding in the standalone GitHub Action Dockerfile and adding bundled passive rules.
- `noir rules update` now emits feedback messages when rules are already up to date.
- Refreshed AI provider metadata for newer models like `gemini-3.5-flash` with warnings for unknown models.
- Updated documentation across all guides to emphasize the new v1 command structure.
- Reorganized delivery and integration flags into **PROBE** (e.g., `--probe`, `--probe-via`) and **EXPORT** (e.g., `--export-es`, `--export-opensearch`, `--export-webhook`) families, preserving old v0 names as aliases.
- Supported custom webhook payload exports via `--export-webhook URL` and OpenSearch exports via `--export-opensearch URL`.
- Internal configuration keys aligned with v1 CLI surface, with automatic migration of legacy YAML config keys.

### Fixed
- Fixed Elasticsearch delivery (`--send-es`) sending empty POST bodies due to Crest body handling issues.
- Fixed false-positive log entries in passive scan AND-branch rules when whole-file gate passed but no line matched.
- Silenced noisy "Detected" logs in passive scan OR-branch rules by logging once per rule/file combination.
- Optimized passive scan regex matching by caching compilation failures instead of retrying regex compilation per line.
- Fixed passive scan rules with empty pattern arrays matching every file.
- Fixed header parsing logic (`--with-headers`) truncation on multi-colon values.
- Fixed various bugs across Deliver, OutputBuilder, Tagger, Passive Scan, and ConfigInitializer layers.
- Improved `noir cache clear` feedback to report the count of deletion failures.
- Made `LLM::Cache.store` writes atomic via a temp file swap to prevent cache corruption.
- Restructured `LLM::Cache` commands to filter strictly on `.json` files.
- Allowed leading/trailing whitespace in `NOIR_CACHE_DISABLE` env var.

### Analyzer Accuracy
- **String Interpolation in Route Paths**: Standardized path normalization across Python, Ruby, PHP, Crystal, Elixir, and Kotlin/Ktor to properly parse interpolated variables as `{name}` placeholders rather than leaking syntax or dropping segments.
- **`Any` / `All` Verb Fan-out**: Method-agnostic endpoints (e.g., Gin `r.Any`, Express `app.all`, Echo `e.Any`, Fiber `app.All`) are now expanded into seven canonical HTTP methods (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS) to improve compatibility with downstream tooling.
- **False-Positive Prevention**: Avoided extracting routes from code comments and string literals in Ruby (Sinatra, Hanami) and PHP (Laravel) analyzers.
- **ASP.NET Multi-line Attribute Stitching**: Supported multi-line ASP.NET routing attributes by joining split lines before applying route patterns.
- **Monorepos Rails `public/*.html` Discovery**: Updated public directory resolution to locate static assets in Rails monorepos.

### Removed
- Removed deprecated `--ollama URL` and `--ollama-model NAME` flags (use `--ai-provider ollama` instead).
- Removed standalone `github-action/Dockerfile` (now unified in the repo-root `Dockerfile`).

### Compatibility
- Legacy `--include-*` and `--set-pvalue*` flags remain fully supported as silent aliases in v1.x.
- Executing `noir` with no arguments now displays the top-level CLI overview instead of raising an error.
- Endpoint JSON output is backward-compatible with v0 and contains only additive fields (`callees`, `ai_context`).
- Maintained existing Docker image tagging conventions and environmental variables (`NOIR_HOME`, `NOIR_AI_KEY`, `NO_COLOR`, etc.) as well as the config paths under `~/.config/noir/` (passive_rules, cache/ai, config.yaml).

## v0.30.0

### Added
- Tree-sitter foundation: vendored grammars for Java, Kotlin, JavaScript, and Python
- Tree-sitter Query API for declarative detectors
- ImportGraph module: unified Java/Kotlin cross-file resolution, relative-import support, Python half
- 30+ new framework analyzers:
  - Java/Kotlin: JAX-RS, Quarkus, Dropwizard, Micronaut, Javalin, Spark Java, http4k, Kotlin Gateway
  - Node.js/JS/TS: Next.js, Hapi, Astro, SvelteKit, Remix, Fresh, Elysia, AdonisJS
  - Python: Bottle, Falcon, Starlette, aiohttp, Pyramid, Litestar
  - Ruby: Roda, Grape
  - PHP: Slim, Yii2, CodeIgniter
  - Go: Iris, Hertz
  - Rust: Poem
  - C++: Crow, Drogon
  - Dart: Dart Frog
- MCP endpoint tagger
- `--exclude-path` flag to filter files by glob
- Crystal 1.20 support
- RPM, DEB, APK, and AUR package release workflows
- Shared engine base classes for PHP, Ruby, Rust, Elixir, Swift, Crystal, Scala, JavaScript, Python, and Go analyzers
- Analyzer architecture documentation

### Changed
- Migrated Spring, Armeria, Ktor, and Flask analyzers to tree-sitter; retired legacy Java/Kotlin miniparser/minilexer
- Migrated Python and Go route extraction to tree-sitter
- Switched builder to official `crystallang/crystal` (Alpine) image
- Consolidated duplicate `Endpoint` initializers
- AI provider docs and Ollama model token map updates (gemma3/4, llama4, phi4)
- **GHCR image tag convention** changed from `vX.Y.Z` to `X.Y.Z` to align with the OCI/Docker standard. `:latest`, `:0.30`, and `:0.30.0` are published; the historical `:v0.30.0` form is no longer produced. Update any pinned references accordingly.

### Performance
- Cached file contents in `CodeLocator` for analyzer reuse
- Parse-once Spring/Kotlin extractors with shared DTO sibling cache
- Skip already-matched detectors in the per-file detect loop
- Pruned ignored directories at walk time and deduped media stats
- Passive scan early-out per matcher
- Migrated unified_ai, example, fasthttp, phoenix, and Python analyzers to `file_map`
- Skip non-`.rb` files in Sinatra analyzer

### Fixed
- Bounded recursion depth in tree-walker extractors (security)
- Added boundary check to `ImportGraph.resolve_relative_import` (security)
- Express config-array mount pattern resolution
- JS miniparser: reject bare-identifier routes from `Promise.all`, accept wildcard/bare param routes
- Go miniparser: accept grouped routes without leading slash, guarantee separator on single-match group prefix
- OAS2 analyzer: merged duplicate form/formData branches and corrected `form` → `json` param-type mapping
- Non-deterministic endpoint dedup in Nitro and Nuxt.js analyzers
- Elevated regex compile failures from debug to warn in passive scan
- GraphQL analyzer now uses `Log.debug` instead of `STDERR.puts`
- Warn when falling back to default `max_tokens` for unknown models
- Corrected `SKIPPED_LEAVES` constant spelling in Fresh analyzer

## v0.29.1

### Added
- `getAttribute`, `getHeader`, `getCookies` extraction to JSP analyzer

### Changed
- Propagate import depth for `NOIR_PARSER_MAX_DEPTH` in Java/Kotlin Spring analyzers
- Move `parser.classes` merge outside loop in `process_package_classes`

### Fixed
- Fixed PHP superglobals incorrectly used in JSP analyzer patterns
- Fixed inaccurate line numbers in Express.js analyzer

## v0.29.0

### Added
- Salvo (Rust) framework support
- Hono (Node.js) framework support
- Nitro.js framework support
- httprouter (Go) framework support
- GoFrame (Go) framework support
- gRPC specification analyzer and detector
- Cross-file route analysis for Go analyzers
- Kemal namespace and mount routing support
- `NOIR_PARSER_MAX_DEPTH` environment variable to cap import-following depth
- Framework auth taggers
- Framework taggers

### Changed
- Improved scan performance with buffered channels, optimized file handling, and parallel taggers
- Refactored Go framework analyzers for clarity, consistency, and reduced duplication
- Improved detector coverage and reduced false positives
- Tightened Symfony detector heuristics
- Refined JSP XML detection
- Used `sarif.cr` library for SARIF output
- Upgraded snapcraft base to core24

### Fixed
- Fixed `--only-techs` to accept canonical tech keys
- Fixed floating point exception when `ai_max_token` is 0
- Fixed JS parser false-positive routes from HTTP client calls and nested expressions
- Fixed Kotlin Spring flaky test caused by non-deterministic `Dir.glob` ordering
- Fixed cross-file group resolution bugs in Go analyzers
- Fixed Chi mounted router parameter extraction

## v0.28.0

### Added
- AI Agent Mode for autonomous analysis
- ACP (Agent Communication Protocol) integration
- CakePHP framework support
- Goyave (Go) framework support
- Cross-file Express router analysis
- Enhanced Flask analyzer (Blueprint support)
- Enhanced Tornado analyzer improvements
- Enhanced Chi analyzer (mounted router parameter extraction)
- Enhanced Kotlin Spring analyzer improvements

### Changed
- Refactored AI integration architecture

## v0.27.1

### Fixed
- Bug fix for dot base path (`-b .`)
- CI pipeline updates

## v0.27.0

### Added
- NuxtJS framework support
- TanStack Router framework support
- Hummingbird (Swift) framework support
- Kitura (Swift) framework support
- TOML output format
- OpenRouter AI provider support
- `--include-techs` / `--only-techs` flags
- Custom HTML report templates

## v0.26.0

### Added
- Scalatra framework support
- Play Framework support
- Akka HTTP framework support
- Vapor (Swift) framework support
- TypeScript NestJS support
- Postman Collection output format
- HTML output format
- PowerShell output format
- GraphQL tagger
- JWT tagger
- File Upload tagger
- Nix packaging support

## v0.25.1

### Fixed
- ASP.NET MVC attribute routing improvements
- New AI model token limits support

## v0.25.0

### Added
- SARIF output format
- Postman Collection analyzer
- Expanded parameter type support for multiple frameworks
- Multiple `-b` (base path) flags support
- AI adapter pattern refactor

## v0.24.0

### Added
- 17 new framework support: Marten, Grip, Amber, Plug, go-zero, fasthttp, Vert.x, NestJS, Ktor, Symfony, Laravel, Tornado, Sanic, Gotham, Tide, Warp
- Passive scan severity filter
- AI response cache system
- GitHub Action support
- Korean documentation
- Project mascot "Hak"

## v0.23.1

### Added
- Method-based filtering for Deliver

## v0.23.0

### Added
- Loco (Rust) framework support
- RWF (Rust) framework support
- FeignClient support
- Mermaid diagram output format
- Express dynamic path support

### Changed
- Documentation migrated from Hugo to Zola

## v0.22.0

### Added
- GraphQL SDL analyzer
- Koa.js framework support
- HTTP method validation

### Changed
- Migrated from Rakefile to justfile

## v0.21.1

### Added
- `--ai-max-token` flag for AI integration

### Fixed
- Bug fixes for AI analyzer
- Documentation migrated from Jekyll to Hugo

## v0.21.0

### Added
- Fastify framework support
- Express/Restify router-based route detection

### Changed
- AI analyzer bundling (71% faster for large projects)

## v0.20.1

### Fixed
- JSON/YAML OutputBuilder bug fix
- Unit testing improvements

## v0.20.0

### Added
- Expanded AI support (OpenAI, xAI, GitHub Models, LM Studio)
- `.http` file analysis
- Chi (Go) framework support
- `--verbose` flag
- `--help-all` flag

## v0.19.1

### Changed
- Docker base image changed to Debian

### Fixed
- Ollama JSON format fixes
- `--exclude-techs` flag fix

## v0.19.0

### Added
- AI/LLM integration via Ollama
- ZAP Sites Tree analyzer
- Improved Express/Restify analyzers

### Changed
- Improved concurrency handling

## v0.18.3

### Fixed
- Django URL handling fixes
- Spring URL handling fixes
- Enhanced `--list-techs` output
- DAST pipeline documentation

## v0.18.2

### Fixed
- URL normalization fix
- Shell completion update
- `--no-log` improvement

## v0.18.1

### Changed
- Config/options parser refactor

### Fixed
- Bug fix (#440)

## v0.18.0

### Added
- Passive Scan feature
- Status codes flags (`--status-codes`)
- Actix Web (Rust) framework support
- Path parameter detection improvements
- Fish shell completion

### Changed
- Modularized codebase structure

## v0.17.0

### Added
- Documentation site
- `--only-tag` flag
- `application.properties` parsing for Spring

### Changed
- Improved output format

## v0.16.1

### Fixed
- Fixed diff endpoint comparison (#330)

### Changed
- OWASP project migration

## v0.16.0

### Added
- Config home directory support (`~/.config/noir`)
- Kotlin Spring parameter analysis
- Shell completions (Bash, Zsh)
- Diff mode for comparing endpoints
- `--build-info` flag

## v0.15.1

### Fixed
- Performance improvements
- Bug fixes (#293, #298)

## v0.15.0

### Added
- Restify (Node.js) framework support
- Beego (Go) framework support
- Rocket (Rust) framework support
- CORS tagger
- SOAP tagger
- WebSocket tagger
- ARM64 Docker image support

## v0.14.0

### Added
- Tagger system (hunt, oauth)
- HAR format analysis support

## v0.13.0

### Added
- MiniLexer for Java/Golang parsing
- Snapcraft packaging support

### Changed
- Improved Go Gin/Fiber/Echo group route handling

## v0.12.2

### Added
- `--config` flag for configuration file
- MiniLexer tokenizer

### Changed
- Improved OAS3 analyzer

## v0.12.1

### Added
- New output formats: `only-url`, `only-param`, `only-header`, `only-cookie`, `jsonl`

## v0.12.0

### Added
- FileAnalyzer with hooks (string/base64 detection)
- Go Fiber framework support
- `--include-path` flag

### Removed
- Removed `--scope` flag

## v0.11.0

### Added
- Ruby Hanami framework support
- Elixir Phoenix framework support
- Crystal Lucky framework support
- Cookie parameter type
- `--concurrency` flag for parallel processing

## v0.10.0

### Added
- Rust Axum framework support
- `--use-matchers` flag
- `--use-filters` flag

## v0.9.1

### Fixed
- OAS2/OAS3 analyzer bug fixes
- RAML analyzer bug fixes
- Express analyzer bug fixes

## v0.9.0

### Added
- FastAPI (Python) framework support
- ElasticSearch deliver
- YAML output format

## v0.8.0

### Added
- `--with-headers` flag
- OAS2/OAS3 output formats

### Changed
- Output builder refactor

## v0.7.3

### Added
- ZAP deliver support

### Fixed
- OAS2 bug fix (#102)

## v0.7.2

### Fixed
- Dir.glob exception fix (#95)

## v0.7.1

### Fixed
- OAS3 bug fix (#90)

## v0.7.0

### Added
- Kotlin Spring framework support
- Java Armeria framework support
- C# ASP.NET MVC framework support

### Changed
- Improved Django analyzer
- Improved Flask analyzer

## v0.6.0

### Added
- Go Gin framework support
- RAML specification support
- JSP analyzer
- Go Echo header support

## v0.5.4

### Changed
- Improved PHP analyzer (POST parameters, headers)

## v0.5.3

### Changed
- Improved PHP analyzer

## v0.5.2

### Changed
- Improved Django analyzer
- Improved Spring analyzer
- Improved Go Echo analyzer
- Improved Rails analyzer
- Testing refactor

## v0.5.1

### Fixed
- File access error exception handling

## v0.5.0

### Added
- OpenAPI Specification 3.0 support
- Header identification support

### Changed
- OAS 2.0 naming transition (from Swagger)

## v0.4.0

### Added
- Swagger (JSON/YAML) analysis support
- CodeLocator singleton pattern

## v0.3.0

### Added
- `--exclude-techs` flag
- Tech metadata management

## v0.2.4

### Fixed
- UTF-8 encoding bug fix
- Django prefix handling fix
- Spring scanning fix

## v0.2.3

### Changed
- Improved Spring analyzer
- Improved Go Echo analyzer

## v0.2.2

### Changed
- Improved Django analyzer

## v0.2.1

### Added
- Parameter support for Kemal/Sinatra
- Endpoint Reference type

## v0.2.0

### Added
- Crystal Kemal framework support
- WebSocket endpoint type

## v0.1.0

### Added
- Initial release
- Framework support: Django, Spring, Rails, Sinatra, Go Echo, Express, Flask, PHP
- CLI interface with `-b` (base path) and `-u` (base URL) flags
- JSON output format
- Multiple technology detection

