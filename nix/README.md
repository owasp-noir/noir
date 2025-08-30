# Nix Support for OWASP Noir

This directory contains Nix expressions for building and packaging OWASP Noir.

## Files

- `../flake.nix` - Modern Nix flake definition with development shell and package
- `../default.nix` - Traditional Nix derivation for building Noir
- `../shell.nix` - Development shell for traditional Nix users
- `overlay.nix` - Example overlay for integrating with nixpkgs
- `../flake.lock` - Pinned flake inputs

## Usage

### Using Nix Flakes

```bash
# Install from the repository
nix profile install github:owasp-noir/noir

# Run without installing
nix run github:owasp-noir/noir -- --help

# Development environment
nix develop
```

### Using Traditional Nix

```bash
# Build the package
nix-build

# Install the package
nix-env -f default.nix -i

# Development shell
nix-shell
```

### For Nixpkgs Maintainers

The `default.nix` can be used as a basis for adding Noir to nixpkgs. The `overlay.nix` shows how to integrate it into the package set.

## Development

The development shell includes:
- Crystal compiler
- Shards dependency manager  
- Just build tool
- Ameba linter

All the standard development commands work in the Nix shell:
- `just build` - Build the application
- `just test` - Run tests
- `just check` - Format and lint code