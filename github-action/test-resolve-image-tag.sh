#!/usr/bin/env bash
# ============================================================================
# Unit tests for resolve-image-tag.sh — pure, no Docker/registry needed.
# ============================================================================
#
# Usage:  github-action/test-resolve-image-tag.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$HERE/resolve-image-tag.sh"

fail_count=0
check() {
  local ref="$1" want="$2" got
  # stderr (degrade warnings) is intentionally discarded — only the tag on
  # stdout is the contract.
  got="$(bash "$RESOLVE" "$ref" 2>/dev/null)"
  if [ "$got" = "$want" ]; then
    printf '    \033[32m✓\033[0m %-42s -> %s\n' "ref='${ref}'" "$got"
  else
    printf '    \033[31m✗\033[0m %-42s -> %s (want %s)\n' "ref='${ref}'" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

echo "resolve-image-tag.sh"

# Release refs: strip a leading v, map to the unprefixed published tags.
check "v1.1.0"      "1.1.0"
check "1.1.0"       "1.1.0"
check "v1"          "1"
check "v1.1"        "1.1"
check "v2.0.0-rc1"  "2.0.0-rc1"

# Empty ref (local `uses: ./`, unpinned consumer) -> latest.
check ""            "latest"

# Commit-SHA pins -> latest (no per-commit image is published).
check "a1b2c3d"                                    "latest"
check "0123456789abcdef0123456789abcdef01234567"  "latest"

# Branch refs pass through verbatim; action.yml's pull step falls back to
# :latest if the branch has no published image.
check "main"        "main"
check "feature/x"   "feature/x"

echo
if [ "$fail_count" -eq 0 ]; then
  echo "All resolver checks passed."
else
  echo "$fail_count resolver check(s) failed." >&2
  exit 1
fi
