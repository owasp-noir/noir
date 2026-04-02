# Changelog

All notable changes to [Noir](https://github.com/owasp-noir/noir) will be documented in this file.

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

