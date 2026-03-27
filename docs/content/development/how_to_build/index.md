+++
title = "How to Build"
description = "Set up a development environment, build from source, run tests, and contribute to OWASP Noir."
weight = 1
sort_by = "weight"

+++

All contributions are welcome — bug fixes, features, and documentation improvements.

## How to Contribute

1.  **Fork** the [Noir repository](https://github.com/owasp-noir/noir)
2.  **Create a branch**
    ```sh
    git checkout -b your-feature-name
    ```
3.  **Make changes**
4.  **Commit** with a clear message
5.  **Push** to your fork
    ```sh
    git push origin your-feature-name
    ```
6.  **Open a Pull Request** with a description

See [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) for detailed guidelines.

## Development Setup

### Installing Crystal

Noir is built with Crystal. Install it for your platform.

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### Other Platforms
See the [official Crystal installation guide](https://crystal-lang.org/install/).

### Building and Testing

Clone your fork and install dependencies with `shards`, Crystal's package manager.

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

Build the project. The compiled binary ends up at `./bin/noir`.

```sh
shards build
```

Run the test suite with Crystal's built-in test runner.

```sh
crystal spec

# For more detailed output
crystal spec -v
```

### Linting

Noir uses [Ameba](https://github.com/crystal-ameba/ameba), a static analysis tool for Crystal.

```sh
bin/ameba.cr
```

Auto-fix issues.

```sh
bin/ameba.cr --fix
```

Or use `just`.

```sh
just fix
```
