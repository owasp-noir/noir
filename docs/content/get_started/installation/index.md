+++
title = "Installation"
description = "Learn how to install OWASP Noir on your system. This guide provides instructions for installing Noir using Homebrew, Snapcraft, Docker, or by building from source."
weight = 2
sort_by = "weight"

[extra]
+++

There are several ways to install OWASP Noir, so you can choose the method that works best for your operating system and workflow.

## Homebrew (macOS and Linux)

If you are on macOS or Linux, the easiest way to install Noir is with [Homebrew](https://brew.sh/).

```bash
brew install noir
```

{% alert_info() %}
For Homebrew users, shell completions for Zsh, Bash, and Fish are automatically installed, so you can start using them right away.
{% end %}

## Snapcraft (Linux)

If you are on a Linux distribution that supports [Snap](https://snapcraft.io/), you can install Noir from the Snap Store.

```bash
sudo snap install noir
```

## Nix

If you use [Nix](https://nixos.org/), you can install Noir using Nix flakes or the traditional Nix expressions.

### Using Nix Flakes (Recommended)

```bash
# Install directly from the repository
nix profile install github:owasp-noir/noir

# Or run without installing
nix run github:owasp-noir/noir -- --help
```

### Using Traditional Nix

```bash
# Clone the repository first
git clone https://github.com/owasp-noir/noir
cd noir

# Install using Nix
nix-env -f default.nix -i

# Or enter a development shell
nix-shell
```

### Development Environment

For development, you can use the provided Nix flake or shell.nix:

```bash
# Using flakes
nix develop

# Using traditional shell.nix
nix-shell
```

## Docker

If you prefer to use Docker, you can pull the official Noir image from the GitHub Container Registry (GHCR).

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

You can find a list of all available tags on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Build from Source

{% alert_warning() %}
If you want to build Noir from source, you will need to have the Crystal programming language installed.
{% end %}

1.  **Clone the repository**:

    ```bash
    git clone https://github.com/owasp-noir/noir
    cd noir
    ```

2.  **Install dependencies**:

    ```bash
    shards install
    ```

3.  **Build the project**:

    ```bash
    shards build --release --no-debug
    ```

    The compiled binary will be located at `./bin/noir`.

## Verifying the Installation

Once you have installed Noir, you can verify that it is working correctly by running:

```bash
noir --version
```

This should print the installed version of Noir.
