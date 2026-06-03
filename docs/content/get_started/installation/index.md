+++
title = "Install Noir"
description = "Install OWASP Noir via Homebrew, Snapcraft, Docker, Nix, AUR, .deb, .rpm, .apk, binary download, or from source."
weight = 2
sort_by = "weight"
prev_page_path = "/get_started/overview/"
prev_page_label = "What is Noir?"
next_page_path = "/get_started/running/"
next_page_label = "Your First Scan"

+++

{% mascot(mood="think") %}
Noir is a single binary with no runtime dependencies. Homebrew is the quickest way for most users, but pick whatever fits your system.
{% end %}

Every method below installs the same `noir` binary, so you only need one. They're ordered roughly easiest-first — find the row that matches your platform and package manager, and skip the rest.

## Homebrew (macOS and Linux)

The easiest option. Noir has an official [Homebrew formula](https://formulae.brew.sh/formula/noir).

To install:

```bash
brew install noir
```

To update:

```bash
brew upgrade noir
```

{% alert_info() %}
Shell completions for Zsh, Bash, and Fish are automatically installed.
{% end %}

## Snapcraft (Linux)

[Snap](https://snapcraft.io) packages work across most Linux distros and auto-update in the background.

To install:

```bash
sudo snap install noir
```

To update manually:

```bash
sudo snap refresh noir
```

## Docker

Handy when you don't want to install anything on the host, or need Noir inside a CI/CD pipeline.

To pull/update the latest image:

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

Scan the current directory:

```bash
docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp
```

Image tags follow the OCI/Docker convention without the `v` prefix, e.g. `:0.30.0`, `:0.30`, and `:latest`. (Versions up to v0.29.1 used the `:vX.Y.Z` form; update any pinned references.) All available tags are on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Nix

If you use [Nix](https://nixos.org), install via Flakes.

To install:

```bash
nix profile add github:owasp-noir/noir
```

To update:

```bash
nix profile upgrade github:owasp-noir/noir
```

{% alert_info() %}
**Tip:** In Docker or restricted environments, you may need to enable experimental features. Use the command below.
{% end %}

```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```

Or run once without installing:

```bash
nix run github:owasp-noir/noir -- -h
```

## Direct Binary Download

No package manager? Grab a prebuilt binary from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Linux and macOS builds are provided.

To install or update:

1. Download the archive for your platform (e.g., `noir-linux-x86_64.tar.gz` or `noir-macos-universal.tar.gz`).
2. Extract:

    ```bash
    tar xzf noir-*.tar.gz
    ```

3. Move or overwrite the existing binary in your `PATH`:

    ```bash
    sudo mv noir /usr/local/bin/
    ```

4. Verify:

    ```bash
    noir --version
    ```

## Debian Package (.deb)

Debian/Ubuntu users can use the `.deb` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). It integrates with `dpkg`/`apt` like any other system package. Both `amd64` and `arm64` are provided.

To install or update:

1. Resolve the latest version and download:

    ```bash
    VERSION=$(curl -s https://api.github.com/repos/owasp-noir/noir/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    wget "https://github.com/owasp-noir/noir/releases/download/v${VERSION}/noir_${VERSION}_amd64.deb"
    ```

2. Install or upgrade:

    ```bash
    sudo dpkg -i "noir_${VERSION}_amd64.deb"
    ```

3. Fix missing dependencies if needed:

    ```bash
    sudo apt-get -f install
    ```

4. Verify:

    ```bash
    noir --version
    ```

## Arch Linux (AUR)

Noir is officially published on the [AUR](https://aur.archlinux.org/packages/noir).

To install or update:

```bash
yay -S noir
```

## RPM Package (.rpm)

Fedora, RHEL, CentOS, openSUSE, and other RPM-based distros can use the `.rpm` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Both `x86_64` and `aarch64` are provided.

To install:

1. Resolve the latest version and download:

    ```bash
    VERSION=$(curl -s https://api.github.com/repos/owasp-noir/noir/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    wget "https://github.com/owasp-noir/noir/releases/download/v${VERSION}/noir-${VERSION}.x86_64.rpm"
    ```

2. Install:

    ```bash
    sudo rpm -i "noir-${VERSION}.x86_64.rpm"
    ```

    Or with `dnf`:

    ```bash
    sudo dnf install "./noir-${VERSION}.x86_64.rpm"
    ```

To update:

1. Download the latest version as shown in the install step.
2. Upgrade:

    ```bash
    sudo rpm -U "noir-${VERSION}.x86_64.rpm"
    ```

    Or with `dnf`:

    ```bash
    sudo dnf upgrade "./noir-${VERSION}.x86_64.rpm"
    ```

3. Verify:

    ```bash
    noir --version
    ```

## Alpine Package (.apk)

Alpine Linux users can use the `.apk` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Both `x86_64` and `aarch64` are provided.

To install or update:

1. Resolve the latest version and download:

    ```bash
    VERSION=$(curl -s https://api.github.com/repos/owasp-noir/noir/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    wget "https://github.com/owasp-noir/noir/releases/download/v${VERSION}/noir-${VERSION}-x86_64.apk"
    ```

2. Install or upgrade:

    ```bash
    sudo apk add --upgrade --allow-untrusted "noir-${VERSION}-x86_64.apk"
    ```

3. Verify:

    ```bash
    noir --version
    ```

## Build from Source

For custom builds or contributing back to the project.

{% alert_warning() %}
Requires [Crystal](https://crystal-lang.org/install/) programming language installed.
{% end %}

To install:

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
    shards build --release
    ```

    The compiled binary is at `./bin/noir`.

To update:

1.  **Pull latest changes:**

    ```bash
    git pull
    ```

2.  **Install dependencies and rebuild:**

    ```bash
    shards install
    shards build --release
    ```

## Verify Your Installation

Whichever method you chose, confirm Noir is installed:

```bash
noir --version
```

If you see a version number, you're ready.

---

**Next**: [Your First Scan](@/get_started/running/index.md)
