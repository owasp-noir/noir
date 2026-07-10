#!/usr/bin/env bash
#
# Verify that every "Edit this page on GitHub" link points at a file that
# actually exists.
#
# hwaro exposes no source-file path to templates, so page.html and section.html
# rebuild it from page.url plus the page language. That derivation is only safe
# if something checks it: a leaf page is <url>/index.md, a section is
# <url>/_index.md, and Korean twins carry a .ko suffix. Get any of that wrong
# and the link silently 404s on GitHub.
#
# Requires a build first:
#   cd docs && hwaro build
#
# Usage:
#   docs/scripts/check_edit_links.sh              # default: docs/public + docs/content
#   docs/scripts/check_edit_links.sh PUBLIC CONTENT

set -euo pipefail

PUBLIC="${1:-docs/public}"
CONTENT="${2:-docs/content}"
PREFIX="https://github.com/owasp-noir/noir/edit/main/docs/content"

if [[ ! -d "$PUBLIC" ]]; then
  echo "ERROR: build output not found: $PUBLIC (run 'cd docs && hwaro build')" >&2
  exit 2
fi

total=0
missing=()

while IFS= read -r href; do
  total=$((total + 1))
  rel="${href#"$PREFIX"}"
  if [[ ! -f "$CONTENT$rel" ]]; then
    missing+=("$href  ->  $CONTENT$rel")
  fi
done < <(grep -rhoE "${PREFIX}[^\"]+" "$PUBLIC" --include='*.html' | sort -u)

if [[ $total -eq 0 ]]; then
  echo "ERROR: no edit links found in $PUBLIC; did the template change?" >&2
  exit 1
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Broken edit links (${#missing[@]} of $total):"
  printf '  %s\n' "${missing[@]}"
  exit 1
fi

echo "Edit links OK: all $total point at existing files."
