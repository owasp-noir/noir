# ❤️ Contributing to Noir

Thank you for contributing to OWASP Noir!

## Quick Start

1. **Fork** the repository
2. **Create branch** and make changes
3. **Test** your changes locally
4. **Submit PR** to main branch with clear description

## 🛠️ Development

### Setup

```bash
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

### Build

```bash
shards build  # Binary: ./bin/noir
```

### Test

```bash
crystal spec       # Run tests
crystal spec -v    # Verbose output
```

### Lint

```bash
crystal tool format && ameba --fix
# or
just fix
```

## 📁 Repository Structure

```
spec/               # Tests
  unit_test/        # Unit tests
  functional_test/  # Functional tests
src/                # Source code
  analyzer/         # Endpoint & parameter analysis
  detector/         # Language & framework detection
  models/           # Data structures
```

## 📚 Documentation

Website: [owasp-noir.github.io/noir](https://owasp-noir.github.io/noir/)

### Local Development

```bash
# Install Zola: https://www.getzola.org/documentation/getting-started/installation/
just docs-serve  # Serves at http://localhost:1313
```

Submit documentation PRs to the main branch.
