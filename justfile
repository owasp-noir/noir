alias b := build
alias ds := docs-serve
alias dsup := docs-supported
alias vc := version-check
alias vu := version-update

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

# Clean build artifacts (tree-sitter objects, bin/, lib/).
[group('build')]
clean:
    rm -f src/ext/tree_sitter/runtime/*.o
    rm -f src/ext/tree_sitter/grammars/*/*.o
    rm -rf bin/
    rm -rf lib/

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
    lib/ameba/bin/ameba.cr --fix

# Check code format and lint without changes.
[group('development')]
check:
    crystal tool format --check
    lib/ameba/bin/ameba.cr

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

# Run uncovered tests only (not included in CI).
[group('development')]
test-uncovered:
    crystal spec spec/uncovered_test

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/check_version_consistency.cr

# Update version across all files (uses shard.yml version, or specify new version).
[group('development')]
version-update VERSION="":
    @if [ -z "{{VERSION}}" ]; then crystal run scripts/version_update.cr; else crystal run scripts/version_update.cr -- {{VERSION}}; fi
