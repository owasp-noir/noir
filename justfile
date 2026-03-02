alias b := build
alias ds := docs-serve
alias dsup := docs-supported
alias vc := version-check

# List available tasks.
default:
    @just --list

# Build noir binary.
[group('build')]
build:
    shards build

# Update shards.nix.
[group('build')]
nix-update:
    nix-shell -p crystal2nix --run crystal2nix

# Serve docs site locally.
[group('documents')]
docs-serve:
    hwaro serve -i docs --base-url="http://localhost:3000"

# Generate supported technology docs from techs.cr.
[group('documents')]
docs-supported:
    crystal run scripts/generate_supported_docs.cr

# Generate supported docs and serve the site.
[group('documents')]
docs-serve-supported: docs-supported docs-serve

# Check for missing i18n documentation files.
[group('documents')]
docs-i18n-check:
    crystal run scripts/check_i18n_docs.cr

# Install docs dependencies (macOS).
[group('documents')]
docs-dependencies:
    brew install hahwul/hwaro/hwaro

# Auto-format code and fix lint issues.
[group('development')]
fix:
    crystal tool format
    bin/ameba.cr --fix

# Check code format and lint without changes.
[group('development')]
check:
    crystal tool format --check
    bin/ameba.cr

# Run all tests.
[group('development')]
test:
    crystal spec spec/unit_test
    crystal spec spec/functional_test

# Run unit tests only.
[group('development')]
test-unit:
    crystal spec spec/unit_test

# Run functional tests only.
[group('development')]
test-func:
    crystal spec spec/functional_test

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/check_version_consistency.cr
