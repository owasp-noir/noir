---
title: Release Procedure
has_children: false
nav_order: 2
layout: page
---

# Release Procedure

## Release Targets

| Name             | Package Name & Link     |                           |
|------------------|-------------------------|---------------------------|
| Homebrew         | [noir](https://formulae.brew.sh/formula/noir)                    | Manual                    |
| Homebrew (tap)   | noir                    | Automated (Github action) |
| Snapcraft        | [noir](https://snapcraft.io/noir)                    | Automated (Github action) |
| Docker (ghcr.io) | [ghcr.io/owasp-noir/noir](https://github.com/owasp-noir/noir/pkgs/container/noir) | Automated (Github action) |
| OWASP Project Page | [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir) | Manual |

## Procedure
1. Check the package version in noir command and documents.
2. Create a release on GitHub.
3. Most releases are automated, handle only the items that require manual release.

## Manual releases
### Homebrew 
#### Step-by-Step Guide
1. Fork the Homebrew core repository: [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core)
> For personal use: Sync your fork (e.g., [hahwul/homebrew-core](https://github.com/hahwul/homebrew-core))

2. Generate a PR for the Homebrew core:
```bash
brew bump-formula-pr --strict --version <VERSION> noir
# Example: brew bump-formula-pr --strict --version 0.19.1 noir
```

#### Troubleshooting
If you encounter issues, try the following commands:
```bash
HOMEBREW_NO_INSTALL_FROM_API=1 brew update
brew bump-formula-pr --strict --version 0.19.1 noir
```

#### Style Check
To ensure your changes adhere to Homebrew's style guidelines:
```bash
cd $(brew --repository)/Library/Taps/homebrew/homebrew-core/Formula
brew style noir.rb
```

### OWASP Project Page
1. Sync your fork of the OWASP Noir project page: [owasp-noir/www-project-noir](https://github.com/owasp-noir/www-project-noir)
2. Update the contents as needed.
3. Create a PR to the main repository: [OWASP/www-project-noir](https://github.com/OWASP/www-project-noir)