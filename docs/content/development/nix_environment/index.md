+++
title = "Build with Nix Env"
description = "Set up a reproducible development environment for OWASP Noir using Nix and Docker."
weight = 2
sort_by = "weight"

+++

Nix provides a reproducible development environment: the same dependencies on every machine, isolated from system-wide packages.

## Installing Nix

The multi-user (daemon) install is recommended; it supports concurrent builds and better isolation. The single-user option is simpler but skips the background daemon.

```sh
# Multi-user installation (recommended for Linux/macOS)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Single-user installation
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

See the [official Nix installation guide](https://nixos.org/download.html) for details.

## Setup with Nix Flakes

### Enable Flakes

[Flakes](https://wiki.nixos.org/wiki/Flakes) are Nix's modern approach to reproducible project definitions. Enable them by adding this line to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`).

```
experimental-features = nix-command flakes
```

### Enter Development Shell

```sh
cd noir
nix develop
```

The shell brings its own Crystal, shards, `just`, and the native libraries Noir links against. The shard dependencies themselves still live in `./lib`, so install them once inside the shell and build as usual.

```sh
shards install
just build
```

## Alternative: Using Docker with Nix

If you'd rather not install Nix on your host, use the official Nix Docker image. This mounts your local repo into the container.

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

Inside the container, enter the dev shell.

```sh
nix develop
```

## Building the Package

The flake also builds the release binary, exactly as `nix profile add github:owasp-noir/noir` does for users. Same flags as every other official build: `--release --no-debug`.

```sh
just nix-build
./result/bin/noir -h
```

## Updating Dependencies

`shards.nix` pins every dependency of the Nix build by revision and hash, and it is generated rather than hand-written. Regenerate it whenever `shard.lock` changes, then verify the two agree.

```sh
just nix-update
just nix-check
```

CI runs the same check, so a forgotten regeneration surfaces in review instead of in the first Nix install after release.

To move the pinned nixpkgs forward — and with it the Crystal toolchain the package builds against:

```sh
nix flake update
```

## Next Steps

Proceed with the standard [build and test procedures](../how_to_build/).
