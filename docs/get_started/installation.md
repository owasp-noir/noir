---
title: Installation
parent: Get Started
has_children: false
nav_order: 1
toc: true
layout: page
---

{% include toc.md %}

## Installation
### Homebrew
Homebrew is the package manager for MacOS(or linux). On devices using homebrew, you can easily install/update using the brew command.

```shell
/bin/bash -c "(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

If the Homebrew already exists or has been installed, install noir through the brew command.

```shell
brew install noir

# https://formulae.brew.sh/formula/noir
```

### Snapcraft

```shell
sudo snap install noir

# https://snapcraft.io/noir
```

### Build from source
#### Install Crystal-lang

> [https://crystal-lang.org/install/](https://crystal-lang.org/install/)

#### Clone this repo
```bash
git clone https://github.com/owasp-noir/noir
cd noir
```

#### Build
```bash
# Install Dependencies
shards install

# Build
shards build --release --no-debug

# Copy binary
cp ./bin/noir /usr/bin/
```

### Docker (GHCR)

```bash
docker pull ghcr.io/owasp-noir/noir:main
```

## Run noir

```bash
noir -b <BASE_PATH>

# noir -b .
# noir -b ./app_directory
```