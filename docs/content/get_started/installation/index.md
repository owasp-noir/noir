+++
title = "Installation"
description = "Learn how to install OWASP Noir on your system. This guide provides instructions for installing Noir using Homebrew, Snapcraft, Docker, Nix, or by building from source."
weight = 2
sort_by = "weight"

[extra]
+++

Choose your preferred installation method:

## Homebrew (macOS and Linux)

Install using [Homebrew](https://brew.sh/):

```bash
brew install noir
```

{% alert_info() %}
Shell completions for Zsh, Bash, and Fish are automatically installed.
{% end %}

## Snapcraft (Linux)

Install from [Snap Store](https://snapcraft.io/):

```bash
sudo snap install noir
```

## Docker

Pull from GitHub Container Registry:

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

See all available tags on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Nix

Install using [Nix](https://nixos.org/):

```bash
nix profile install github:owasp-noir/noir
```

Or run directly:

```bash
nix run github:owasp-noir/noir -- -h
```

## Unofficial

### Arch AUR

Install from [AUR](https://aur.archlinux.org/packages/noir):

```bash
yay -S noir
```

## Build from Source

{% alert_warning() %}
Requires Crystal programming language installed.
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
