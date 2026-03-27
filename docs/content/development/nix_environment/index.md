+++
title = "Build with Nix Env"
description = "Set up a reproducible development environment for OWASP Noir using Nix and Docker."
weight = 2
sort_by = "weight"

+++

Nix provides a reproducible development environment with consistent dependencies across machines.

## Installing Nix

The multi-user (daemon) install is recommended — it supports concurrent builds and better isolation. The single-user option is simpler but skips the background daemon.

```sh
# Multi-user installation (recommended for Linux/macOS)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Single-user installation
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

See the [official Nix installation guide](https://nixos.org/download.html) for details.

## Setup with Nix Flakes

### Enable Flakes

[Flakes](https://nixos.wiki/wiki/Flakes) are Nix's modern approach to reproducible project definitions. Enable them by adding this line to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`).

```
experimental-features = nix-command flakes
```

### Enter Development Shell

```sh
cd noir
nix develop
```

This sets up Crystal, shards, and all dependencies automatically.

## Alternative: Using Docker with Nix

If you'd rather not install Nix on your host, use the official Nix Docker image. This mounts your local repo into the container.

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

Inside the container, enter the dev shell.

```sh
nix develop
```

## Updating Dependencies

After modifying `shard.yml`, regenerate `shards.nix` to keep Nix in sync.

```sh
nix-shell -p crystal2nix --run crystal2nix
```

## Benefits

- **Reproducibility**: Same environment across all machines
- **Isolation**: No interference with system-wide dependencies
- **Consistency**: All team members use the same tool versions
- **Easy Setup**: Single command to get started

## Next Steps

Proceed with the standard [build and test procedures](../how_to_build/).
