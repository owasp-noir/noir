+++
title = "Contributing to Noir"
description = "Learn how to contribute to the OWASP Noir project. This guide provides instructions on how to set up your development environment, build the project, and submit your first pull request."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir is a community-driven project, and we welcome contributions of all kinds. Whether you are fixing a bug, adding a new feature, or improving the documentation, your help is greatly appreciated.

## How to Contribute

The best way to contribute is to follow these steps:

1.  **Fork the repository**: Start by creating your own copy of the [Noir repository](https://github.com/owasp-noir/noir) on GitHub.
2.  **Create a new branch**: Create a new branch in your fork for your changes.
    ```sh
    git checkout -b your-feature-or-fix-name
    ```
3.  **Make your changes**: Make your changes to the code or documentation.
4.  **Commit your changes**: Commit your changes with a clear and descriptive commit message.
5.  **Push your changes**: Push your changes to your fork.
    ```sh
    git push origin your-feature-or-fix-name
    ```
6.  **Create a Pull Request**: Open a pull request from your fork to the main Noir repository. Please provide a clear description of the changes you have made.

For more detailed guidelines, please see our official [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) file.

## Development Setup

If you are contributing to the code, you will need to set up a local development environment.

### Installing Crystal

Noir is built with the Crystal programming language. To install it, please follow the official [Crystal installation guide](https://crystal-lang.org/install/).

### Building and Testing

Once you have Crystal installed, you can clone the repository and install the dependencies:

```sh
# Clone your fork
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir

# Install dependencies
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
