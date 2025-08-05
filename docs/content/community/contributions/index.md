+++
title = "Contributions"
description = "Collection of articles and blog posts about Noir written by community members"
weight = 1
sort_by = "weight"

[extra]
+++

## Installing Crystal Language

To install Crystal Language, please refer to the official [Crystal installation guide](https://crystal-lang.org/install/). The guide provides instructions for various operating systems and package managers.

## Build & Testing

### Clone and Install Dependencies

```sh
# If you've forked this repository, clone to https://github.com/<YOU>/noir
git clone https://github.com/hahwul/noir
cd noir
shards install
```

### Build

```sh
shards build
# ./bin/noir
```

### Unit/Functional Test

```sh
crystal spec

# Want more details?
crystal spec -v
```

### Lint

```sh
crystal tool format
ameba --fix

# Ameba installation
# https://github.com/crystal-ameba/ameba#installation
```

or

```sh
just fix
```

## How to Contribute

We welcome contributions from the community. To contribute, follow these steps:

1. **Fork the repository**: Click the "Fork" button at the top right of the repository page.
2. **Clone your fork**:
   ```sh
   git clone https://github.com/your-username/noir.git
   cd noir
   ```
3. **Create a new branch**:
   ```sh
   git checkout -b your-branch-name
   ```
4. **Make your changes**: Implement your changes and commit them with a descriptive message.
5. **Push your changes**:
   ```sh
   git push origin your-branch-name
   ```
6. **Create a Pull Request**: Go to the original repository and click the "New Pull Request" button. Fill out the template and submit your pull request.

For more detailed guidelines, please refer to our [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) file.
