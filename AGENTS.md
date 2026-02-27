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
docker run --rm -v $(pwd):/app -w /app 84codes/crystal:latest-debian-13 sh -c "shards install && shards build"

# Local install (Ubuntu/Debian)
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt install -y just
```

## Usage

```bash
./bin/noir -h                                           # Help (includes all output formats)
./bin/noir --list-techs                                 # List all supported technologies
./bin/noir --list-taggers                               # List available taggers
./bin/noir -b path/to/source                            # Basic analysis
./bin/noir -b . -f json                                 # JSON output (see -h for all formats)
./bin/noir -b . --verbose                               # Detailed analysis
./bin/noir -b . -P                                      # Passive security scan
./bin/noir -b . --send-proxy http://127.0.0.1:8080     # Forward to proxy (Burp/ZAP)
./bin/noir -b . --ai-provider openai --ai-model gpt-4  # AI-powered analysis
```

## Repository Structure

```
src/
├── analyzer/analyzers/     # Endpoint/parameter analyzers by language/framework
├── detector/detectors/     # Technology detection by language/framework
├── output_builder/         # Output format generation (JSON, YAML, OAS, etc.)
├── models/                 # Data structures (includes delivers/, minilexer/)
├── llm/                    # AI/LLM integration (general/, ollama/)
├── optimizer/              # Endpoint normalization/dedup and LLM optimizer
├── tagger/taggers/         # Endpoint tagging implementations
├── deliver/                # Results delivery (proxy, elasticsearch)
├── minilexers/             # Custom lexers
├── miniparsers/            # Custom parsers
├── passive_scan/           # Passive security scanning
├── techs/                  # Supported technologies catalog
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

## Adding New Components

### Analyzers
1. Create `src/analyzer/analyzers/{language}/{framework}.cr`
2. Add functional test: `spec/functional_test/testers/{language}/{framework}_spec.cr`
3. Add fixtures: `spec/functional_test/fixtures/{language}/{framework}/`
4. Register in `src/analyzer/analyzer.cr` if needed
5. Update `src/techs/techs.cr` with technology metadata

### Detectors
1. Create `src/detector/detectors/{language}/{framework}.cr`
2. Add unit test: `spec/unit_test/detector/{language}/{framework}_detector_spec.cr`
3. Register in `src/detector/detector.cr` if needed
4. Update `src/techs/techs.cr` with technology metadata

### Output Formats
1. Create `src/output_builder/{format}_builder.cr`
2. Add unit test: `spec/unit_test/output_builder/{format}_builder_spec.cr`
3. Register in output builder selection logic
4. Update `src/options.cr` help text

### Taggers
1. Create `src/tagger/taggers/{tagger_name}.cr`
2. Add unit test: `spec/unit_test/tagger/{tagger_name}_spec.cr`
3. Register in tagger registry

**After any new component: run `just test` to validate.**

## Before Committing

1. `just build` - Ensure compilation succeeds
2. `just test` - Ensure all tests pass
3. `crystal tool format` - Format code
4. Verify basic functionality: `./bin/noir -b spec/functional_test/fixtures/crystal`

## Environment
- Crystal ~> 1.19 (CI: 1.19.0)
- Docker image: `84codes/crystal:latest-debian-13`
- Dependencies: `libyaml-dev`, `libzstd-dev`, `zlib1g-dev`, `pkg-config`
