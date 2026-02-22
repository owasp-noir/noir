# OWASP Noir - Attack Surface Detector

OWASP Noir is a Crystal-based attack surface detector that identifies endpoints by static analysis of source code across multiple programming languages and frameworks.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Bootstrap, Build, and Test
**NEVER CANCEL BUILDS OR TESTS - Follow exact timing guidelines below:**

1. **Install Crystal and dependencies:**
   ```bash
   # Using Docker (recommended for consistent builds)
   docker run --rm -v $(pwd):/app -w /app 84codes/crystal:latest-debian-13 sh -c "shards install && shards build"
   docker run --rm -v $(pwd):/app -w /app 84codes/crystal:latest-debian-13 crystal spec

   # Or install Crystal locally (Ubuntu/Debian)
   curl -fsSL https://crystal-lang.org/install.sh | sudo bash
   sudo apt install -y just
   ```

2. **Build the application:**
   ```bash
   just build
   # OR: shards build
   ```
   - **Timing: ~30 seconds. NEVER CANCEL. Set timeout to 120+ seconds.**

3. **Run tests:**
   ```bash
   just test
   # OR: crystal spec
   ```
   - **Timing: ~10 seconds. NEVER CANCEL. Set timeout to 60+ seconds.**

### Run the Application

- **Basic usage:**
  ```bash
  ./bin/noir -h                    # Show help
  ./bin/noir --version             # Show version
  ./bin/noir --list-techs          # List supported technologies
  ```

- **Analyze source code:**
  ```bash
  ./bin/noir -b path/to/source                              # Basic analysis
  ./bin/noir -b . -f json                                   # JSON output format
  ./bin/noir -b . -f yaml                                   # YAML output format
  ./bin/noir -b . --verbose                                 # Detailed analysis (+ include-path + all-taggers)
  ./bin/noir -b . -P                                        # Enable passive security scan
  ./bin/noir -b . --ai-provider openai --ai-model gpt-4    # AI-powered analysis
  ./bin/noir -b . --send-proxy http://127.0.0.1:8080       # Forward to proxy (Burp/ZAP)
  ```

- **Available output formats:**
  - `plain` - Plain text (default)
  - `json` - JSON format
  - `jsonl` - JSON Lines
  - `yaml` - YAML format
  - `toml` - TOML format
  - `markdown-table` - Markdown table
  - `sarif` - SARIF format
  - `html` - HTML report
  - `curl` - cURL commands
  - `httpie` - HTTPie commands
  - `powershell` - PowerShell Invoke-WebRequest commands
  - `oas2` - OpenAPI 2.0 (Swagger)
  - `oas3` - OpenAPI 3.0
  - `postman` - Postman collection
  - `only-url` - Only endpoint URLs
  - `only-param` - Only parameters
  - `only-header` - Only headers
  - `only-cookie` - Only cookies
  - `only-tag` - Only tags
  - `mermaid` - Mermaid diagram

### Development Commands

- **Formatting and linting:**
  ```bash
  crystal tool format              # Format code
  bin/ameba.cr                     # Run linter
  ```

- **Using just commands:**
  ```bash
  just --list                      # List available commands
  just build                       # Build application
  just test                        # Run tests
  just check                       # Format check + lint
  just fix                         # Auto-format + fix lint issues
  ```

## Validation

### Always test these scenarios after making changes:
1. **Build and run basic analysis:**
   ```bash
   just build && ./bin/noir -b spec/functional_test/fixtures/crystal
   ```
   - Should detect Crystal frameworks (kemal, lucky, amber, grip, marten)
   - Should find endpoints with parameters

2. **Test JSON output:**
   ```bash
   ./bin/noir -b spec/functional_test/fixtures/crystal -f json
   ```
   - Should produce valid JSON with endpoints array

3. **Run full test suite:**
   ```bash
   just test
   ```
   - Should pass all tests
   - **Timing: ~10 seconds. NEVER CANCEL.**

4. **Technology detection:**
   ```bash
   ./bin/noir --list-techs | head -10
   ```
   - Should list supported frameworks and languages
   
5. **List available taggers:**
   ```bash
   ./bin/noir --list-taggers
   ```
   - Shows available taggers for endpoint categorization

## Common Tasks

### Repository Structure
```
src/                     # Core source code
├── analyzer/            # Code analyzers for endpoint/parameter analysis
│   └── analyzers/       # Analyzer implementations by language/framework
├── detector/            # Technology and framework detection
│   └── detectors/       # Detector implementations by language/framework
├── output_builder/      # Output format generation (JSON, YAML, OAS, etc.)
├── models/              # Data structures and models
│   ├── delivers/        # Delivery-related models
│   └── minilexer/       # Minilexer models
├── llm/                 # AI/LLM integration
│   ├── general/         # General LLM functionality
│   └── ollama/          # Ollama-specific integration
├── optimizer/           # Endpoint optimization (normalization/dedup) and LLM optimizer
├── tagger/              # Endpoint tagging and categorization
│   └── taggers/         # Tagger implementations
├── deliver/             # Results delivery (proxy, elasticsearch)
├── minilexers/          # Custom lexers for parsing
├── miniparsers/         # Custom parsers for parsing
├── passive_scan/        # Passive security scanning functionality
├── techs/               # Supported technologies catalog
├── utils/               # Utility functions
├── banner.cr            # Banner display
├── completions.cr       # Shell completion generation
├── config_initializer.cr # Configuration initialization
├── options.cr           # CLI options parser
└── noir.cr              # Main application entry point

spec/                    # Test code
├── functional_test/     # End-to-end tests
│   ├── fixtures/        # Sample code for testing (crystal, python, javascript, etc.)
│   └── testers/         # Test implementations
└── unit_test/           # Unit tests
    ├── analyzer/        # Analyzer unit tests
    ├── detector/        # Detector unit tests
    ├── llm/             # LLM unit tests
    ├── minilexer/       # Minilexer unit tests
    ├── models/          # Models unit tests
    ├── optimizer/       # Optimizer unit tests
    ├── options/         # Options unit tests
    ├── output_builder/  # Output builder unit tests
    ├── passive_scan/    # Passive scan unit tests
    ├── tagger/          # Tagger unit tests
    ├── techs/           # Techs unit tests
    └── utils/           # Utils unit tests

docs/                    # Zola-based documentation
├── config.toml          # Zola configuration
├── content/             # Documentation content
├── static/              # Static assets
└── themes/              # Zola themes

bin/                     # Compiled binary location
lib/                     # Dependencies (managed by shards)
scripts/                 # Utility scripts
github-action/           # GitHub Action integration
snap/                    # Snap package configuration
```

### Key Files
- `shard.yml`: Dependencies and project metadata (current version: 0.28.0)
- `justfile`: Task definitions and commands (build, test, check, fix, docs-serve, etc.)
- `src/noir.cr`: Main application entry point
- `src/options.cr`: CLI options and argument parsing
- `.ameba.yml`: Linting configuration
- `Dockerfile`: Docker build configuration (uses debian-13)
- `.github/workflows/ci.yml`: CI configuration (uses debian-13, Crystal 1.17.0, 1.18.0, 1.19.0)

### Adding New Analyzers
1. Create analyzer in `src/analyzer/analyzers/{language}/{framework}.cr`
   - Implement endpoint detection logic
   - Extract parameters, methods, and paths
2. Add functional test in `spec/functional_test/testers/{language}/{framework}_spec.cr`
   - Test endpoint detection
   - Verify parameter extraction
3. Add test fixtures in `spec/functional_test/fixtures/{language}/{framework}/`
   - Include sample code representing typical framework usage
4. Register analyzer in `src/analyzer/analyzer.cr` if needed
5. Update `src/techs/techs.cr` with technology metadata
6. Run `just test` to validate
7. Update documentation if needed

### Adding New Detectors
1. Create detector in `src/detector/detectors/{language}/{framework}.cr`
   - Implement technology detection logic (file patterns, imports, etc.)
2. Add unit test in `spec/unit_test/detector/{language}/{framework}_detector_spec.cr`
   - Test detection accuracy
   - Test false positive prevention
3. Register detector in `src/detector/detector.cr` if needed
4. Update `src/techs/techs.cr` with technology metadata
5. Run `just test` to validate
6. Update documentation if needed

### Adding New Output Formats
1. Create output builder in `src/output_builder/{format}_builder.cr`
2. Add unit test in `spec/unit_test/output_builder/{format}_builder_spec.cr`
3. Register format in output builder selection logic
4. Update `src/options.cr` to include new format in help text
5. Run `just test` to validate

### Adding New Taggers
1. Create tagger in `src/tagger/taggers/{tagger_name}.cr`
2. Add unit test in `spec/unit_test/tagger/{tagger_name}_spec.cr`
3. Register tagger in tagger registry
4. Run `just test` to validate

## Critical Notes

### Timing Guidelines
- **NEVER CANCEL** any build or test operations
- Build: ~30 seconds (set 120+ second timeout)
- Tests: ~10 seconds (set 60+ second timeout)
- Analysis: Sub-second for small projects

### Before Committing
1. Run `just build` to ensure compilation
2. Run `just test` to ensure all tests pass
3. Run `crystal tool format` for code formatting
4. Test basic functionality with sample fixtures
5. If adding new analyzers/detectors, update documentation

### Environment
- Crystal ~> 1.10 (CI tests with 1.17.0, 1.18.0, 1.19.0)
- Docker images:
  - CI tests: `84codes/crystal:latest-debian-13`
  - Dockerfile build: `84codes/crystal:latest-debian-13`
- Ubuntu/Debian recommended for local development
- Required dependencies: `libyaml-dev`, `libzstd-dev`, `zlib1g-dev`, `pkg-config`

### Supported Languages and Frameworks
Noir supports endpoint detection across multiple languages and frameworks:
- **Python**: Flask, FastAPI, Django, Sanic, Tornado
- **JavaScript**: Express, Fastify, Koa, Restify, NestJS
- **TypeScript**: NestJS
- **Ruby**: Rails, Sinatra, Hanami
- **Crystal**: Kemal, Lucky, Amber, Grip, Marten
- **Go**: Echo, Gin, Fiber, Gorilla Mux, Chi, Beego, fasthttp, go-zero
- **Rust**: Actix-web, Axum, Rocket, Warp, RWF, Loco, Tide, Gotham
- **Java**: Spring, JSP, Armeria, Vert.x, Play Framework
- **Kotlin**: Spring, Ktor
- **C#**: ASP.NET (Core MVC, MVC)
- **PHP**: Laravel, Symfony, Pure PHP
- **Elixir**: Phoenix, Plug
- **Swift**: Vapor, Kitura, Hummingbird
- **Scala**: Akka HTTP, Scalatra, Play Framework
- **Specifications**: OpenAPI (2.0/3.0), Postman Collections, HAR files, RAML, GraphQL

See `./bin/noir --list-techs` for the complete current list.

### Key Features
- **Endpoint Discovery**: Static analysis to find all endpoints in source code
- **Parameter Extraction**: Identifies query, path, header, cookie, form, and JSON body parameters
- **AI Integration**: LLM support for advanced analysis (OpenAI, xAI, GitHub Models, Azure, Ollama, LM Studio, vLLM)
- **Passive Security Scanning**: Built-in security rule checking
- **Tagging**: Categorize and tag endpoints for better organization
- **Multiple Output Formats**: JSON, YAML, OpenAPI, SARIF, HTML, Markdown, cURL, HTTPie, Postman, etc.
- **Integration Support**: Forward results to Burp Suite, ZAP, or Elasticsearch
- **Diff Mode**: Compare endpoint changes between code versions
- **Shell Completion**: Generate completion scripts for Zsh, Bash, Fish
