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

# Serve the documentation site using Hwaro.
docs-serve:
    @echo "Serving the documentation site at http://localhost:3000/ ..."
    hwaro serve -i docs --base-url="http://localhost:3000"

# Generate supported docs directly from NoirTechs::TECHS (no build required).
docs-supported:
    @echo "Generating supported docs from techs.cr..."
    crystal run scripts/generate_supported_docs.cr

# Generate supported docs and then serve the docs (no build required).
docs-serve-supported: docs-supported
    @echo "Serving the documentation site at http://localhost:3000/ ..."
    hwaro serve -i docs --base-url="http://localhost:3000"

# Check for missing i18n (Korean) documentation files.
docs-i18n-check:
    @echo "Checking for missing i18n documentation files..."
    crystal run scripts/check_i18n_docs.cr

docs-dependencies:
    @echo "Install docs dependencies"
    brew install hahwul/hwaro/hwaro

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
