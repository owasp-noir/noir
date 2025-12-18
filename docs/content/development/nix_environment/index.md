+++
title = "Build with Nix Env"
description = "Set up a reproducible development environment for OWASP Noir using Nix and Docker."
weight = 2
sort_by = "weight"

[extra]
+++

You can set up a reproducible development environment using Nix. This approach ensures consistency across different development machines and simplifies dependency management.

## Installing Nix

If you don't have Nix installed, install it with:

```sh
# Multi-user installation (recommended for Linux/macOS)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Single-user installation
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

For more details, see the [official Nix installation guide](https://nixos.org/download.html).

## Setup with Nix Flakes

The project uses Nix Flakes for development environment management.

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

This will automatically set up Crystal, shards, and all dependencies.

## Alternative: Using Docker with Nix

For a completely isolated environment, you can use Docker:

```sh
docker run -it --rm -v $(pwd):/workspace -w /workspace nixos/nix bash
```

Inside the container, activate the development environment:

```sh
nix develop
```

This will set up all the necessary dependencies and tools for developing Noir in an isolated, reproducible environment.

## Benefits

- **Reproducibility**: Same environment across all machines
- **Isolation**: No interference with system-wide dependencies
- **Consistency**: Ensures all team members use the same tool versions
- **Easy Setup**: Single command to get started

## Next Steps

Once your Nix environment is set up, you can proceed with the standard [build and test procedures](../how_to_build/).
