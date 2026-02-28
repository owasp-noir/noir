+++
title = "How to Release"
description = "Maintainer guide for creating and publishing new Noir releases."
weight = 4
sort_by = "weight"

+++

Release process for project maintainers.

## Release Channels

| Channel | Package Name & Link | Release Process |
|---|---|---|
| Homebrew (Core) | [noir](https://formulae.brew.sh/formula/noir) | Manual |
| Homebrew (Tap) | `owasp-noir/noir` | Automated |
| Snapcraft | [noir](https://snapcraft.io/noir) | Automated |
| Docker Hub | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | Automated |
| OWASP Project Page | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | Manual |

## General Procedure

1.  **Update Version**: Update the version in source code and documentation.
2.  **Verify Version Consistency**: Run the version check to ensure all files match:

    ```bash
    just version-check
    # or
    just vc
    ```

    All 13 tracked files must match the version in `shard.yml` (all checks show ✅).

3.  **Create GitHub Release**: Publish a new release on the [GitHub releases page](https://github.com/owasp-noir/noir/releases). This triggers automated workflows.
4.  **Manual Releases**: Complete the manual steps below for non-automated channels.

## Manual Release Instructions

### Homebrew (Core)

Submit a PR to `homebrew-core`:

1.  **Fork and Sync**: Keep your fork of [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) up-to-date.
2.  **Run the Bump Command**:

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # Example: brew bump-formula-pr --strict --version 0.28.0 noir
    ```

3.  **Style Check** (Optional):

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP Project Page

Submit a PR to [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) with updated content.
