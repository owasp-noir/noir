# Default task, lists all available tasks.
default:
    @echo "Listing available tasks..."
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

# Automatically format code and fix linting issues.
fix:
    @echo "Formatting code and fixing linting issues..."
    crystal tool format
    ameba --fix

# Check code formatting and run linter without making changes.
check:
    @echo "Checking code format and running linter..."
    crystal tool format --check
    ameba

# Run all Crystal spec tests.
test:
    @echo "Running tests..."
    crystal spec
