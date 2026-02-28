+++
title = "Build with Nix Env"
description = "Set up a reproducible development environment for OWASP Noir using Nix and Docker."
weight = 2
sort_by = "weight"

+++

Nix provides a reproducible development environment with consistent dependencies across machines.

## Installing Nix

```sh
# Multi-user installation (recommended for Linux/macOS)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Single-user installation
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

See the [official Nix installation guide](https://nixos.org/download.html) for details.

## Setup with Nix Flakes

### Enable Flakes

Add to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`):

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

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

Inside the container:

```sh
nix develop
```

## Updating Dependencies

After modifying `shard.yml`, regenerate `shards.nix` to keep Nix in sync:

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
