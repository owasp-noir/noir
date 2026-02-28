+++
title = "Installation"
description = "Learn how to install OWASP Noir on your system. This guide provides instructions for installing Noir using Homebrew, Snapcraft, Docker, Nix, or by building from source."
weight = 2
sort_by = "weight"

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
nix profile add github:owasp-noir/noir
```

{% alert_info() %}
**Tip:** In Docker or restricted environments, you may need to enable experimental features:
```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```
{% end %}

Or run directly:

```bash
nix run github:owasp-noir/noir -- -h
```

## Direct Binary Download

You can download the latest prebuilt binaries directly from the
[GitHub Releases page](https://github.com/owasp-noir/noir/releases/latest).

1. Download the appropriate archive for your platform (for example, `noir-linux-x86_64.tar.gz` or `noir-macos-universal.tar.gz`).
2. Extract the archive:

    ```bash
    tar xzf noir-*.tar.gz
    ```

3. Move the `noir` binary somewhere on your `PATH`, for example:

    ```bash
    sudo mv noir /usr/local/bin/
    ```

4. Verify the installation:

    ```bash
    noir --version
    ```

## Debian Package (.deb)

For Debian and Ubuntu (or derivatives), you can install Noir using the `.deb` package from the
[GitHub Releases page](https://github.com/owasp-noir/noir/releases/latest).

1. Download the latest `.deb` package (for example, `noir_latest_amd64.deb`):

    ```bash
    wget https://github.com/owasp-noir/noir/releases/latest/download/noir_latest_amd64.deb
    ```

2. Install the package:

    ```bash
    sudo dpkg -i noir_latest_amd64.deb
    ```

3. If there are missing dependencies, fix them with:

    ```bash
    sudo apt-get -f install
    ```

4. Verify the installation:

    ```bash
    noir --version
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
