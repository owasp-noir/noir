+++
title = 'Installation'
weight = 2
icon = "rocket"
+++

## Overview

You can install Noir using various package managers. Each method has its advantages depending on your operating system and preferences. You can use Homebrew on macOS, Snapcraft or Homebrew on Linux, and on all operating systems including Windows, you can use Docker or build from source.

## Homebrew

Homebrew is the recommended package manager for macOS and Linux. On devices using homebrew, you can easily install and update Noir using the brew command.

If you don't have Homebrew installed yet, you can install it with:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

Once Homebrew is installed, you can install Noir with:

```bash
brew install noir
```

### Shell Completion for Homebrew Users

For Homebrew users, shell completion (for Zsh, Bash, etc.) is installed automatically, and no additional configuration is needed. The completions are ready to use immediately after installation.

## Snapcraft

Snapcraft is a powerful package manager for Linux that enables you to easily install and manage applications. It supports a wide range of distributions, making software installation simple and consistent.

### Install Snapcraft

First, ensure you have Snap installed on your system:

#### Ubuntu
```bash
sudo apt update
sudo apt install snapd
```

#### Other Linux Distributions
For other Linux distributions, please refer to the [official Snapcraft documentation](https://snapcraft.io/docs/installing-snapd).

### Install Noir with Snapcraft

Once you have Snapcraft installed, you can install Noir with:

```bash
sudo snap install noir
```

You can find the Noir package on the [Snapcraft store](https://snapcraft.io/noir).

## Docker (GHCR)

Docker allows you to run Noir in a container without installing it directly on your system. Noir is available on GitHub Container Registry (GHCR).

To pull the latest Noir Docker image:

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

To use a specific version, replace `latest` with the version tag:

```bash
docker pull ghcr.io/owasp-noir/noir:<version>
```

To reference this Docker image in your own Dockerfile:

```dockerfile
FROM ghcr.io/owasp-noir/noir:latest
```

You can find all available Docker tags on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Build from Source

You can build Noir directly from source by following these steps:

### Install Crystal Language

First, install the Crystal programming language from the [official Crystal installation guide](https://crystal-lang.org/install/).

### Clone the Repository

```bash
git clone https://github.com/owasp-noir/noir
cd noir
```

### Build Noir

```bash
# Install Dependencies
shards install

# Build (with release optimizations)
shards build --release --no-debug

# Optional: Copy the binary to your path
sudo cp ./bin/noir /usr/local/bin/
```

After building, you can find the Noir binary at `./bin/noir` in the project directory.

## Verifying Installation

After installation, you can verify that Noir is correctly installed by running:

```bash
noir --version
```

This should display the current version of Noir.

