+++
title = "Install Noir"
description = "Install OWASP Noir via Homebrew, Snapcraft, Docker, Nix, AUR, .deb, .rpm, .apk, binary download (Linux, macOS, Windows), or from source."
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

Every method below installs the same `noir` binary, so pick the one that fits your platform and skip the rest. They're ordered roughly easiest-first.

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
Homebrew also installs shell completions for Zsh, Bash, and Fish.
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
docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest noir scan /tmp
```

Release images are tagged without the `v` prefix: `:1.4.0`, `:1.4`, `:1`, and `:latest`. The `:main` tag tracks the main branch. Versions up to v0.29.1 used the `:vX.Y.Z` form, so update any pinned references. All tags are on the [GitHub Packages page](https://github.com/owasp-noir/noir/pkgs/container/noir).

## Nix

If you use [Nix](https://nixos.org), install via Flakes.

To install:

```bash
nix profile add github:owasp-noir/noir
```

To update:

```bash
nix profile upgrade noir
```

{% alert_info() %}
In Docker or other restricted environments, you may need to enable experimental features first:
{% end %}

```bash
nix --extra-experimental-features "nix-command flakes" profile add github:owasp-noir/noir
```

Or run once without installing:

```bash
nix run github:owasp-noir/noir -- -h
```

## Direct Binary Download

No package manager? Grab a prebuilt binary from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Builds exist for Linux and macOS; Windows (x86_64) builds start with the first release after v1.4.0.

To install or update:

1. Download the binary for your platform (e.g., `noir-v1.4.0-linux-x86_64` on Linux, `noir-v1.4.0-osx-arm64.tar.gz` on macOS, or `noir-vX.Y.Z-windows-x86_64.exe` on Windows).
2. **Linux**: make it executable and move it into your `PATH`:

    ```bash
    chmod +x noir-v*-linux-*
    sudo mv noir-v*-linux-* /usr/local/bin/noir
    ```

3. **macOS**: extract the tarball and keep the bundled `lib/` directory next to the binary:

    ```bash
    # system-wide install
    sudo mkdir -p /opt/noir
    sudo tar xzf noir-v*-osx-*.tar.gz -C /opt/noir
    sudo ln -sf /opt/noir/noir /usr/local/bin/noir
    ```

    For a user-local install without `sudo`, extract under `~/.local/noir` instead and add `~/.local/noir` to your `PATH`.

    The macOS archive ships OpenSSL libraries in `lib/`; do not move only the `noir` binary without them.

4. **Windows**: the `.exe` is self-contained. Rename it to `noir.exe` and put it in a folder on your `PATH`. In PowerShell, for a per-user install:

    ```powershell
    $dir = "$env:LOCALAPPDATA\noir"
    New-Item -ItemType Directory -Force $dir | Out-Null
    Move-Item -Force .\noir-v*-windows-x86_64.exe "$dir\noir.exe"
    [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$dir", "User")
    ```

    Open a new terminal so the updated `PATH` takes effect. To update later, run the `Move-Item` line again with the new download (`-Force` replaces the old `noir.exe`).

5. Verify:

    ```bash
    noir --version
    ```

## Debian Package (.deb)

Debian/Ubuntu users can use the `.deb` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). It integrates with `dpkg`/`apt` like any other system package. Both `amd64` and `arm64` are provided; the commands below use `amd64`, so swap in `arm64` on ARM machines.

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

Fedora, RHEL, CentOS, openSUSE, and other RPM-based distros can use the `.rpm` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Both `x86_64` and `aarch64` are provided; the commands below use `x86_64`, so swap in `aarch64` on ARM machines.

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

Alpine Linux users can use the `.apk` package from [GitHub Releases](https://github.com/owasp-noir/noir/releases/latest). Both `x86_64` and `aarch64` are provided; the commands below use `x86_64`, so swap in `aarch64` on ARM machines.

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
Building from source requires the Crystal programming language.
{% end %}

Install Crystal from [crystal-lang.org](https://crystal-lang.org/install/) first.

**Windows:** the build compiles the bundled Tree-sitter grammars with a small shell script. So besides [Crystal for Windows](https://crystal-lang.org/install/on_windows/), you also need [Git for Windows](https://gitforwindows.org/) (for `sh`) and `clang` (the "C++ Clang tools for Windows" component of Visual Studio Build Tools, or [LLVM](https://releases.llvm.org/)). Run the steps below from Git Bash. The binary is written to `bin\noir.exe`.

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
