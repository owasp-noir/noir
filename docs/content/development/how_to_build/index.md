+++
title = "How to Build"
description = "Learn how to set up your development environment, build the project from source, run tests, and contribute to OWASP Noir."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir welcomes all contributions—bug fixes, features, and documentation improvements.

## How to Contribute

1.  **Fork** the [Noir repository](https://github.com/owasp-noir/noir)
2.  **Create branch**:
    ```sh
    git checkout -b your-feature-name
    ```
3.  **Make changes**
4.  **Commit** with clear message
5.  **Push** to your fork:
    ```sh
    git push origin your-feature-name
    ```
6.  **Open Pull Request** with description

See [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) for detailed guidelines.

## Development Setup

### Installing Crystal

Noir is built with the Crystal programming language. Here are the quick installation methods for common platforms:

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### Other Platforms
For other platforms, see the [official Crystal installation guide](https://crystal-lang.org/install/).

### Building and Testing

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

To build the project, run:

```sh
shards build
# The binary will be located at ./bin/noir
```

To run the unit and functional tests:

```sh
crystal spec

# For more detailed output
crystal spec -v
```

### Linting

We use `ameba` for linting our code. To check the code for style issues, run:

```sh
ameba
```

To automatically fix any style issues, you can run:

```sh
ameba --fix
```

Alternatively, you can use the `just` command to run the linter:

```sh
just fix
```
