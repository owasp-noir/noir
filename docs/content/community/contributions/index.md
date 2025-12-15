+++
title = "Contributing to Noir"
description = "Learn how to contribute to the OWASP Noir project. This guide provides instructions on how to set up your development environment, build the project, and submit your first pull request."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir welcomes all contributions—bug fixes, features, and documentation.

## Quick Start

1. **Fork** the [repository](https://github.com/owasp-noir/noir)
2. **Create branch**: `git checkout -b feature-name`
3. **Make changes** and test
4. **Commit** with clear message
5. **Push**: `git push origin feature-name`
6. **Open PR** with description

See [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) for more details.

## Development Setup

### Install Crystal

Follow the [Crystal installation guide](https://crystal-lang.org/install/).

### Setup, Build & Test

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install    # Install dependencies
shards build      # Binary: ./bin/noir
crystal spec      # Run tests (-v for verbose)
```

### Linting

```sh
ameba --fix       # Auto-fix style issues
# or
just fix          # Format and fix
```
