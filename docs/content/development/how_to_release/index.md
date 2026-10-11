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
| GitHub Container Registry | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | Automated |
| GitHub Release assets | Binaries (Linux, macOS, Windows), `.deb`, `.rpm`, `.apk`, SBOM | Automated |
| AUR | `noir` | Automated |
| OWASP Project Page | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | Semi-automated |

## General Procedure

1.  **Update Version**: Bump the version everywhere it appears (`shard.yml`, `src/noir.cr`, `flake.nix`, the Dockerfile, `snap/snapcraft.yaml`, `aur/PKGBUILD`, the GitHub Action README and a few docs files). The script does it in one go; without an argument it prompts for the new version.

    ```bash
    just version-update 1.4.1
    # or
    just vu 1.4.1
    ```

2.  **Verify Version Consistency**: Run the version check to make sure every file matches:

    ```bash
    just version-check
    # or
    just vc
    ```

    Every tracked file must report the same version as `shard.yml`; the script ends with `✅ All versions match`.

3.  **Create GitHub Release**: Publish a new release on the [GitHub releases page](https://github.com/owasp-noir/noir/releases). Publishing triggers the automated workflows: binaries first, then the `.deb`, `.rpm`, `.apk` and AUR packages once the binaries are uploaded, plus GHCR, Snapcraft, the Homebrew tap and the SBOM.
4.  **Manual Releases**: Complete the manual steps below for the remaining channels.

## Manual Release Instructions

### Homebrew (Core)

Submit a PR to `homebrew-core`:

1.  **Fork and Sync**: Keep your fork of [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core) up-to-date.
2.  **Run the Bump Command**:

    ```bash
    brew bump-formula-pr --strict --version <VERSION> noir
    # Example: brew bump-formula-pr --strict --version 1.4.0 noir
    ```

3.  **Style Check** (Optional):

    ```bash
    cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
    brew style noir.rb
    ```

### OWASP Project Page

The version list on the project page lives in `_data/release.yml` of [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir). For every stable release, the `OWASP Project Page Publish` workflow commits the new tag to the `owasp-noir/www-project-noir` fork and puts a compare link in the run summary. Open the upstream PR from that link by hand: the OWASP Foundation's token policy doesn't let CI create it.

To backfill an older tag or retry a failed run, run the same script locally (`--dry-run` previews the change without pushing):

```bash
just www-release v1.4.0 --dry-run
just www-release v1.4.0
```
