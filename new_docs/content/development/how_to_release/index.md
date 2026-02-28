+++
title = "How to Release"
description = "A guide for maintainers on how to create and publish new releases of Noir. This page outlines the manual and automated steps for releasing to platforms like Homebrew, Snapcraft, and Docker Hub."
weight = 4
sort_by = "weight"

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
| OWASP Project Page | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | Manual |

## General Procedure

1.  **Update Version**: Ensure the package version in the Noir source code and any relevant documentation has been updated.
2.  **Verify Version Consistency**: Before creating a release, run the version consistency check to ensure all files have matching version numbers:

    ```bash
    just version-check
    # or
    just vc
    ```

    This will validate that version strings across all 13 tracked files match the version in `shard.yml`. All checks must pass (show ✅) before proceeding with the release.

3.  **Create GitHub Release**: Create a new release on the [GitHub releases page](https://github.com/owasp-noir/noir/releases). This will trigger the automated release workflows.
4.  **Manual Releases**: Follow the manual release procedures for any channels that are not automated.

## Manual Release Instructions

### Homebrew (Core)

To update the main Homebrew formula, you need to submit a pull request to the `homebrew-core` repository.

1.  **Fork and Sync**: Make sure you have a fork of the [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) repository and that it is up-to-date.
2.  **Run the Bump Command**: Use the `brew bump-formula-pr` command to automatically create a pull request with the new version.

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # Example: brew bump-formula-pr --strict --version 0.28.0 noir
    ```

3.  **Style Check**: (Optional) To ensure your changes meet Homebrew's style guidelines, you can run:

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP Project Page

To update the OWASP project page, you need to submit a pull request to the `OWASP/www-project-noir` repository.

1.  **Fork and Sync**: Fork the [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) repository and make sure it is up-to-date.
2.  **Update Content**: Make any necessary changes to the content of the project page.
3.  **Create Pull Request**: Create a pull request to the main repository.
