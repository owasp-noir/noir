# OWASP Noir - Attack Surface Detector

OWASP Noir is a Crystal-based attack surface detector that identifies endpoints by static analysis of source code across multiple programming languages and frameworks.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Bootstrap, Build, and Test
**NEVER CANCEL BUILDS OR TESTS - Follow exact timing guidelines below:**

1. **Install Crystal and dependencies:**
   ```bash
   sudo apt update
   sudo apt install -y crystal shards just
   ```

2. **Build the application:**
   ```bash
   just build
   # OR: shards build
   ```
   - **Timing: 10 seconds. NEVER CANCEL. Set timeout to 60+ seconds.**

3. **Run tests:**
   ```bash
   just test
   # OR: crystal spec
   ```
   - **Timing: 7 seconds (1384 tests). NEVER CANCEL. Set timeout to 30+ seconds.**

### Run the Application

- **Basic usage:**
  ```bash
  ./bin/noir -h                    # Show help
  ./bin/noir --version             # Show version
  ./bin/noir --list-techs          # List supported technologies
  ```

- **Analyze source code:**
  ```bash
  ./bin/noir -b path/to/source     # Basic analysis
  ./bin/noir -b . -f json          # JSON output format
  ./bin/noir -b . -f yaml          # YAML output format
  ./bin/noir -b . --verbose        # Detailed analysis
  ```

### Development Commands

- **Formatting and linting:**
  ```bash
  crystal tool format              # Format code
  # NOTE: ameba linter has compatibility issues with Crystal 1.11.2
  ```

- **Using just commands:**
  ```bash
  just --list                      # List available commands
  just build                       # Build application (10s)
  just test                        # Run tests (7s)
  just check                       # Format check + lint (NOTE: ameba issues)
  just fix                         # Auto-format + fix lint issues
  ```

## Validation

### Always test these scenarios after making changes:
1. **Build and run basic analysis:**
   ```bash
   just build && ./bin/noir -b spec/functional_test/fixtures/crystal
   ```
   - Should detect crystal_kemal and crystal_lucky technologies
   - Should find ~10 endpoints with parameters

2. **Test JSON output:**
   ```bash
   ./bin/noir -b spec/functional_test/fixtures/crystal -f json
   ```
   - Should produce valid JSON with endpoints array

3. **Run full test suite:**
   ```bash
   just test
   ```
   - Should pass all 1384 tests in ~7 seconds

4. **Technology detection:**
   ```bash
   ./bin/noir --list-techs | head -5
   ```
   - Should list supported frameworks and languages

## Common Tasks

### Repository Structure
```
src/                     # Core source code
├── analyzer/            # Code analyzers for endpoint/parameter analysis
├── detector/            # Technology and framework detection
├── output_builder/      # Output format generation (JSON, YAML, etc.)
├── models/              # Data structures and models
├── llm/                 # AI/LLM integration
├── optimizer/           # Endpoint optimization (normalization/dedup) and LLM optimizer
├── tagger/              # Endpoint tagging and categorization
└── deliver/             # Results delivery (proxy, elasticsearch)

spec/                    # Test code
├── functional_test/     # End-to-end tests
│   ├── fixtures/        # Sample code for testing
│   └── testers/         # Test implementations
└── unit_test/           # Unit tests

docs/                    # Zola-based documentation
bin/                     # Compiled binary location
lib/                     # Dependencies (managed by shards)
```

### Key Files
- `shard.yml`: Dependencies and project metadata
- `justfile`: Task definitions and commands
- `src/noir.cr`: Main application entry point
- `.ameba.yml`: Linting configuration (compatibility issues)

### Adding New Analyzers
1. Create analyzer in `src/analyzer/analyzers/{language}/{framework}.cr`
2. Add functional test in `spec/functional_test/testers/{language}/{framework}_spec.cr`
3. Add test fixtures in `spec/functional_test/fixtures/{language}/{framework}/`
4. Register analyzer in `src/analyzer/analyzer.cr` if needed
5. Update documentation and `src/techs/techs.cr`
6. Run `just test` to validate

### Adding New Detectors
1. Create detector in `src/detector/detectors/{language}/{framework}.cr`
2. Add unit test in `spec/unit_test/detector/{language}/{framework}_detector_spec.cr`
3. Register detector in `src/detector/detector.cr` if needed
4. Update documentation and `src/techs/techs.cr`
5. Run `just test` to validate

## Critical Notes

### Known Issues
- **http_proxy dependency**: Requires manual compatibility fix for Crystal 1.11.2+ (see bootstrap steps)
- **ameba linter**: Has compatibility issues with Crystal 1.11.2, use `crystal tool format` instead
- **Zola docs**: Not installed by default, install separately if needed for documentation work

### Timing Guidelines
- **NEVER CANCEL** any build or test operations
- Build: 10 seconds (set 60+ second timeout)
- Tests: 7 seconds (set 30+ second timeout)
- Analysis: Sub-second for small projects

### Before Committing
1. Run `just build` to ensure compilation
2. Run `just test` to ensure all tests pass
3. Run `crystal tool format` for code formatting
4. Test basic functionality with sample fixtures
5. If adding new analyzers/detectors, update documentation

### Environment
- Crystal ~> 1.10 (tested with 1.11.2)
- Ubuntu 24.04+ recommended
- Requires manual dependency fixes as documented above
