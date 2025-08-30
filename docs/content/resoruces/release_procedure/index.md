+++
title = "Release Procedure"
description = "A guide for maintainers on how to create and publish new releases of Noir. This page outlines the manual and automated steps for releasing to platforms like Homebrew, Snapcraft, and Docker Hub."
weight = 1
sort_by = "weight"

[extra]
+++

This document outlines the process for creating and publishing a new release of Noir. It is intended for project maintainers.

## Release Channels

Noir is distributed through several channels. Some are updated automatically via GitHub Actions, while others require manual intervention.

| Channel | Package Name & Link | Release Process |
|---|---|---|
| Homebrew (Core) | [noir](https://formulae.brew.sh/formula/noir) | Manual |
| Homebrew (Tap) | `owasp-noir/noir` | Automated |
| Snapcraft | [noir](https://snapcraft.io/noir) | Automated |
| Docker Hub | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | Automated |
| Nix | [nixpkgs](https://github.com/NixOS/nixpkgs) | Manual |
| OWASP Project Page | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | Manual |

## General Procedure

1.  **Update Version**: Ensure the package version in the Noir source code and any relevant documentation has been updated.
2.  **Create GitHub Release**: Create a new release on the [GitHub releases page](https://github.com/owasp-noir/noir/releases). This will trigger the automated release workflows.
3.  **Manual Releases**: Follow the manual release procedures for any channels that are not automated.

## Manual Release Instructions

### Homebrew (Core)

To update the main Homebrew formula, you need to submit a pull request to the `homebrew-core` repository.

1.  **Fork and Sync**: Make sure you have a fork of the [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) repository and that it is up-to-date.
2.  **Run the Bump Command**: Use the `brew bump-formula-pr` command to automatically create a pull request with the new version.

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # Example: brew bump-formula-pr --strict --version 0.23.1 noir
    ```

3.  **Style Check**: (Optional) To ensure your changes meet Homebrew's style guidelines, you can run:

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### Nix

To add Noir to the official nixpkgs repository, you need to submit a pull request to the nixpkgs repository.

1.  **Fork and Sync**: Make sure you have a fork of the [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) repository and that it is up-to-date.

2.  **Create Package Expression**: Create a new package expression in the appropriate category. For Noir, this would typically be in `pkgs/tools/security/` or `pkgs/development/tools/`.

3.  **Use crystal2nix**: Use the [crystal2nix](https://github.com/nix-community/crystal2nix) tool to generate or update the Nix expression:

    ```bash
    # Install crystal2nix
    nix-env -iA nixpkgs.crystal2nix
    
    # Generate Nix expression
    crystal2nix > noir.nix
    ```

4.  **Update all-packages.nix**: Add the package to `pkgs/top-level/all-packages.nix`:

    ```nix
    noir = callPackage ../tools/security/noir { };
    ```

5.  **Test the Build**: Before submitting, test that the package builds correctly:

    ```bash
    nix-build -A noir
    ```

6.  **Create Pull Request**: Submit a pull request to the nixpkgs repository following their [contribution guidelines](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md).

### OWASP Project Page

To update the OWASP project page, you need to submit a pull request to the `OWASP/www-project-noir` repository.

1.  **Fork and Sync**: Fork the [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) repository and make sure it is up-to-date.
2.  **Update Content**: Make any necessary changes to the content of the project page.
3.  **Create Pull Request**: Create a pull request to the main repository.
