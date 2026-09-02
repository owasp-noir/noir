alias b := build
alias br := build-release
alias ds := docs-serve
alias dsup := docs-supported
alias vc := version-check
alias vu := version-update
alias bm := benchmark
alias bmf := benchmark-full

# List available tasks.
default:
    @just --list

# Build noir binary (debug; fast incremental compile, slower runtime).
[group('build')]
build:
    shards build

# Build noir binary with --release (slower compile, 2–3x faster runtime; use for benchmarks).
# Uses the same flags as production release builds (Homebrew, GitHub releases, Docker, Snap)
# so that local benchmark comparisons against the global binary are fair.
[group('build')]
build-release:
    shards build --release --no-debug --production

# Regenerate shards.nix from shard.lock (run after changing dependencies).
[group('build')]
nix-update:
    nix-shell -p crystal2nix --run crystal2nix

# Verify shards.nix still pins exactly what shard.lock resolves.
[group('build')]
nix-check:
    crystal run scripts/check_shards_nix.cr

# Build the Nix package the way `nix profile add github:owasp-noir/noir` does.
[group('build')]
nix-build:
    nix build .#default --print-build-logs

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

# Generate supported technology docs and headline counts from the techs catalog.
[group('documents')]
docs-supported:
    crystal run scripts/generate_supported_docs.cr

# Generate supported docs and serve the site.
[group('documents')]
docs-serve-supported: docs-supported docs-serve

# Regenerate the CLI screenshots in the docs (needs a release binary).
[group('documents')]
docs-capture: build-release
    docs/tools/cli-capture/capture.sh

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

# The fastest feedback loop while working on a single analyzer — ~8.5s
# against ~16.5s for the whole suite. Almost all of that is compiling src/,
# not running the test (the run itself is ~0.06s), so narrowing further
# buys nothing.
#
# Run one functional tester, e.g. `just test-func-one javascript/hono`.
[group('development')]
test-func-one TESTER:
    crystal spec spec/functional_test/testers/{{TESTER}}_spec.cr

# Run every functional tester for one language: `just test-func-lang python`.
[group('development')]
test-func-lang LANG:
    crystal spec spec/functional_test/testers/{{LANG}}

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/check_version_consistency.cr

# Update version across all files (uses shard.yml version, or specify new version).
[group('development')]
version-update VERSION="":
    @if [ -z "{{VERSION}}" ]; then crystal run scripts/version_update.cr; else crystal run scripts/version_update.cr -- {{VERSION}}; fi

# The release workflow does this automatically; run it by hand to backfill an
# older tag or retry a failed run. Extra flags are passed through, so
# `just www-release v1.3.1 --dry-run` previews the edit without pushing.
#
# Add a release to the OWASP project page version list (prints the PR link).
[group('development')]
www-release VERSION *ARGS:
    scripts/update_www_release.sh {{VERSION}} {{ARGS}}

# Run benchmarks to compare global and local noir binaries on a large mock codebase.
[group('development')]
benchmark: build-release
    crystal run scripts/benchmark.cr

# Run full benchmarks with multiple analysis flags (--include=path,techs,callee --ai-context -T).
[group('development')]
benchmark-full: build-release
    crystal run scripts/benchmark.cr -- --include=path,techs,callee --ai-context -T


