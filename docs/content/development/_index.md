+++
title = "Development"
description = "Resources for developers contributing to OWASP Noir, including build instructions, development environment setup, debugging tools, and release procedures."
weight = 10
sort_by = "weight"


[cascade]
toc = true

+++

Guides for contributing to Noir: building from source, the analyzer architecture, debug flags, and the release process.

*   **[How to Build](how_to_build/)**: Set up a development environment, build the project, and run the tests.
*   **[Analyzer Architecture](analyzer_architecture/)**: The 3-layer design (engine → route extractor → framework adapter), and a step-by-step guide for adding a new detector/analyzer.
*   **[Build with Nix Env](nix_environment/)**: A reproducible development environment with Nix and Docker.
*   **[Debug with hidden flags](debug_flags/)**: Developer-only flags for debugging and experimentation.
*   **[How to Release](how_to_release/)**: Maintainer guide for creating and publishing releases.
