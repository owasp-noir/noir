+++
title = "Installation"
description = "Install OWASP Noir via Homebrew, Snapcraft, Docker, Nix, binary download, or from source."
weight = 2
sort_by = "weight"

+++

## Homebrew (macOS and Linux)

```bash
brew install noir
```

{% alert_info() %}
Shell completions for Zsh, Bash, and Fish are automatically installed.
{% end %}

## Snapcraft (Linux)

```bash
sudo snap install noir
```

## Docker

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

All available tags are on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Nix

```bash
nix profile add github:owasp-noir/noir
```

{% alert_info() %}
**Tip:** In Docker or restricted environments, you may need to enable experimental features:
```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```
{% end %}

Or run directly without installing:

```bash
nix run github:owasp-noir/noir -- -h
```

## Direct Binary Download

Download prebuilt binaries from the [GitHub Releases page](https://github.com/owasp-noir/noir/releases/latest).

1. Download the archive for your platform (e.g., `noir-linux-x86_64.tar.gz` or `noir-macos-universal.tar.gz`).
2. Extract:

    ```bash
    tar xzf noir-*.tar.gz
    ```

3. Move to a directory on your `PATH`:

    ```bash
    sudo mv noir /usr/local/bin/
    ```

4. Verify:

    ```bash
    noir --version
    ```

## Debian Package (.deb)

For Debian/Ubuntu and derivatives, use the `.deb` package from the [GitHub Releases page](https://github.com/owasp-noir/noir/releases/latest).

1. Download the `.deb` package:

    ```bash
    wget https://github.com/owasp-noir/noir/releases/latest/download/noir_latest_amd64.deb
    ```

2. Install:

    ```bash
    sudo dpkg -i noir_latest_amd64.deb
    ```

3. Fix missing dependencies if needed:

    ```bash
    sudo apt-get -f install
    ```

4. Verify:

    ```bash
    noir --version
    ```

## Unofficial

### Arch AUR

```bash
yay -S noir
```

## Build from Source

{% alert_warning() %}
Requires Crystal programming language installed.
{% end %}

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/owasp-noir/noir
    cd noir
    ```

2.  **Install dependencies:**

    ```bash
    shards install
    ```

3.  **Build:**

    ```bash
    shards build --release --no-debug
    ```

    The compiled binary is at `./bin/noir`.
