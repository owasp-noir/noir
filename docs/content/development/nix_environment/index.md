+++
title = "Build with Nix Env"
description = "Set up a reproducible development environment for OWASP Noir using Nix and Docker."
weight = 2
sort_by = "weight"

[extra]
+++

You can set up a reproducible development environment using Nix and Docker. This approach ensures consistency across different development machines and simplifies dependency management.

## Setup

Run a Nix container with the project directory mounted:

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
