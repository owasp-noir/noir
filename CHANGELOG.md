# Changelog

All notable changes to [Noir](https://github.com/owasp-noir/noir) will be documented in this file.

## v1.0.0

Two motivations for the major bump: noir's analyzer / tagger / passive-scan
surface is now stable enough across the supported framework matrix to
deserve a 1.x line, and the CLI moves from a flag-only layout to a
verb-centric one (`noir scan` / `list` / `cache` / `config` / `rules` /
`completion` / `version` / `help`). The verb introduction is the *only*
intentional design break — every v0 invocation pattern (`noir -b ./app
[flags]`) still works untouched, and the entire v0 → v1 cleanup was
designed around preserving the v0 surface anywhere it could be preserved.
See the [CLI commands reference](docs/content/usage/cli_commands/_index.md)
for the full surface.

### Added
- New subcommand surface:
  - `noir scan PATHS...` — positional paths plus every existing scan flag
  - `noir list techs|taggers|formats` — built-in catalogs
  - `noir cache info|clear|purge` — on-disk LLM response cache;
    `purge <days>` drops entries older than N days
  - `noir config show|edit|init|path` — user-level YAML configuration
  - `noir rules list|update|path` — passive-scan rules repository
  - `noir completion <zsh|bash|fish|elvish>` — shell completion script
  - `noir version [--verbose]` — version number (or build details)
  - `noir help [command]` — top-level overview / per-command help
- `--pvalue TYPE=VAL` (repeatable): unified parameter-value flag covering
  `any` / `header` / `cookie` / `query` / `form` / `json` / `path`
- `--include LIST`: comma-separated enrichment toggle (`path,techs,callee`)
- `--ai-context[=LIST]`: optional comma-separated filter narrowing the
  emitted AI-context categories (`guards`, `sinks`, `validators`,
  `signals`, `callee`) in plain output
- `--no-color` (and the `NO_COLOR` env var) honored as a global flag
  across every subcommand, not just `scan`
- Elvish shell completion alongside zsh / bash / fish
- Endpoint JSON output gains two additive fields: `callees`
  (1-hop call graph populated by analyzers that surface it) and
  `ai_context` (per-endpoint AI review context, present only when
  `--ai-context` is enabled)
- Docker image (`ghcr.io/owasp-noir/noir`) now ships the upstream
  `noir-passive-rules` snapshot baked at `/opt/noir/passive_rules/`,
  so `noir scan -P` works out of the box inside the container without
  git or network. The user-managed `~/.config/noir/passive_rules/`
  still wins when populated; `NOIR_BUNDLED_RULES_PATH` env var lets
  packagers override the bundled location.

### Changed
- Router default-routes any bare-flag invocation to `scan`, preserving
  the v0 `noir -b ./app [flags]` shape for every CI pipeline, GitHub
  Action, Dockerfile entrypoint, and shell alias.
- Terminal v0 flags are silently rewritten to their v1 subcommand
  equivalents: `--list-techs` → `noir list techs`,
  `--list-taggers` → `noir list taggers`,
  `--build-info` → `noir version --verbose`,
  `--generate-completion SHELL` → `noir completion SHELL`,
  `--help-all` → `noir help`.
- Shell completion scripts are now subcommand-aware: `noir <TAB>`
  completes verbs, `noir scan -<TAB>` completes scan flags.
- Default `concurrency` scales with the host's CPU count
  (`System.cpu_count.clamp(4, 32)`) instead of the v0 fixed `"20"`.
  Explicit user configuration is still respected.
- GitHub Action switched from `using: docker` (sibling Dockerfile
  rebuilt on every call) to `using: composite` (docker pull a
  pre-built ghcr image and run). `with:` inputs and outputs are
  unchanged; the first invocation is faster since the jq install no
  longer runs per workflow, and the image tag now tracks
  `github.action_ref` automatically.
- Docker image is self-contained: ships `jq`, `ca-certificates`,
  `/entrypoint.sh`, the passive-rules snapshot, and GitHub Action
  labels. The standalone `github-action/Dockerfile` was folded in.
- `noir rules update` is no longer silent when rules are already up
  to date — emits an explicit success / warning message every time.
- AI provider model metadata refreshed for v1 (gemini-3.5-flash etc.
  added to `MODEL_TOKEN_LIMITS`); unknown models surface a warning
  instead of silently using the default cap.
- Documentation updates across the homepage, getting-started guide,
  troubleshooting, shell-completion, configuration, output-format, and
  AI-provider pages to lead with the v1 idiom (v0 examples preserved
  in compatibility callouts).
- Deliver surface split into two semantic families. `noir scan -h`
  now shows three sections: **PROBE** for active HTTP replay
  against the discovered endpoints, **EXPORT** for shipping the
  catalog to an external data store, and **LEGACY** for the v0
  aliases that map onto them:
    - `--send-req` → `--probe`
    - `--send-proxy URL` → `--probe-via URL`
    - `--with-headers VAL` → `--probe-header VAL`
    - `--use-matchers VAL` → `--probe-match VAL`
    - `--use-filters VAL` → `--probe-skip VAL`
    - `--send-es URL` → `--export-es URL`
  All v0 names remain accepted (silent aliases — same internal
  options keys, no behavior change), so v0.x scripts and
  Dockerfiles keep working. The rename clarifies that
  match/skip/header only affect probing, not the stdout/`-o`
  output.

### Fixed
- `--send-es URL` (Elasticsearch delivery) shipped empty POST bodies
  on every call because Crest's `Request.execute` ignores `body:` and
  only honors `form:`. Switched to `form: body, json: true` — payloads
  now actually reach Elasticsearch.
- Passive scan AND-branch logged "Detected" before per-line
  confirmation, so rules whose whole-file gate passed but matched no
  single line produced false-positive log entries with zero findings.
- Passive scan OR-branch logged "Detected" once per individual hit,
  flooding output on noisy rules. Now logs once per (rule × file).
- Passive scan retried `Regex.new` on every line × file when a
  matcher's regex failed to compile at load time. Failed compilations
  are now sticky; later matches short-circuit to false.
- Passive scan rules with empty `patterns` arrays no longer match
  every file (the prior `matcher.patterns && Array#all?` shape made
  an empty array act as "match everything").
- `--with-headers "Authorization: Bearer x:y:z"` lost everything
  after the first colon. Now splits on the first colon only so
  multi-colon values survive.
- Latent bugs in the Deliver layer (`apply_all` chaining, matcher
  dedup, header propagation, ES header leakage, header parsing).
- Latent bugs in the OutputBuilder layer.
- Latent bugs in the Tagger layer.
- Latent bugs in the Passive Scan layer (whole-content prefilter
  misapplication, others).
- Latent bugs in ConfigInitializer (legacy boolean parsing).
- `noir cache clear` silently dropped partial-delete failures behind
  a single count; now reports the failed count alongside `deleted`.
- `LLM::Cache.store` was not atomic; a crash mid-write corrupted the
  cache entry and forced a spurious retry on the next scan. Writes
  now go through a `.tmp` sibling + `File.rename`.
- `LLM::Cache.clear` / `stats` walked every file in the cache
  directory, so any non-cache file dropped there could be wiped or
  miscounted. Both now filter on `.json`.
- `NOIR_CACHE_DISABLE` tolerates surrounding whitespace.

### Removed
- `--ollama URL` and `--ollama-model NAME` (deprecated since 2024).
  Use `--ai-provider ollama [--ai-model NAME]` instead — the CLI prints
  a one-line migration hint if either flag is passed.
- `github-action/Dockerfile` (folded into the repo-root `Dockerfile`).

### Compatibility
- The legacy `--include-path`, `--include-techs`, `--include-callee`,
  and the seven `--set-pvalue*` flags continue to work as silent
  aliases throughout the v1.x line.
- `noir` with no arguments now prints the top-level overview instead
  of the v0 "Base path is required" error; scripts that intentionally
  relied on the empty-args exit code should pass `noir scan` explicitly.
- Endpoint JSON output is strictly additive — `callees` and
  `ai_context` are new keys; every v0 field is preserved with the
  same semantics. Strict-schema consumers (SARIF strict mode, etc.)
  may need to allow the new keys.
- Docker image tag conventions unchanged (`latest`, `1.0.0`, `1.0`,
  `main`). Pinning the GitHub Action to `@v1.0.0` resolves to ghcr
  tag `1.0.0` and ships the rules snapshot from that release.
- `NOIR_HOME`, `NOIR_AI_KEY`, `NOIR_CACHE_DISABLE`, `NO_COLOR`, and
  the on-disk paths under `~/.config/noir/` (passive_rules, cache/ai,
  config.yaml) are unchanged from v0.

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

