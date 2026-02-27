# Alias

alias b := build
alias ds := docs-serve
alias dsup := docs-supported
alias vc := version-check

# Default task, lists all available tasks.
default:
    @echo "Listing available tasks..."
    @echo "Aliases: b (build), ds (docs-serve), dsup (docs-supported), vc (version-check)"
    @just --list

# Build the application using Crystal Shards.
build:
    @echo "Building the application..."
    shards build

# Serve the documentation site using Zola.

# This requires you to be in the 'docs' directory.
docs-serve:
    @echo "Serving the documentation site at http://localhost:1111/ ..."
    cd docs && zola serve

# Generate supported docs from current ./bin/noir --list-techs output.
docs-supported: build
    @echo "Generating supported docs from --list-techs..."
    crystal run scripts/generate_supported_docs.cr

# Generate supported docs and then serve the docs.
docs-serve-supported: docs-supported
    @echo "Serving the documentation site at http://localhost:1111/ ..."
    cd docs && zola serve

# Check for missing i18n (Korean) documentation files.
docs-i18n-check:
    @echo "Checking for missing i18n documentation files..."
    crystal run scripts/check_i18n_docs.cr

# Automatically format code and fix linting issues.
fix:
    @echo "Formatting code and fixing linting issues..."
    crystal tool format
    bin/ameba.cr --fix

# Check code formatting and run linter without making changes.
check:
    @echo "Checking code format and running linter..."
    crystal tool format --check
    bin/ameba.cr

# Run all Crystal spec tests.
test:
    @echo "Running tests..."
    crystal spec spec/unit_test
    crystal spec spec/functional_test

# Check version consistency across all files using shard.yml as source of truth.
version-check:
    @echo "Checking version consistency..."
    crystal run scripts/check_version_consistency.cr

# Update shards.nix
nix-update:
    nix-shell -p crystal2nix --run crystal2nix
