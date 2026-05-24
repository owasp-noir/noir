#!/usr/bin/env bash
#
# Verify that every English doc page has a Korean counterpart and
# vice versa. Adding a new page in one language without its pair
# leaves the sidebar / footer language switcher pointing at a
# missing URL.
#
# Exits 0 when parity holds, 1 when any file is unpaired. Lists
# every missing pair so the fix is a quick `cp` per line.
#
# Usage:
#   docs/scripts/check_doc_parity.sh              # default — docs/content
#   docs/scripts/check_doc_parity.sh path/to/dir  # override root

set -euo pipefail

ROOT="${1:-docs/content}"
if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: content directory not found: $ROOT" >&2
  exit 2
fi

missing_ko=()
missing_en=()

# Walk every .md file once and classify by suffix.
while IFS= read -r -d '' file; do
  if [[ "$file" == *.ko.md ]]; then
    en="${file%.ko.md}.md"
    if [[ ! -f "$en" ]]; then
      missing_en+=("$file -> $en")
    fi
  else
    ko="${file%.md}.ko.md"
    if [[ ! -f "$ko" ]]; then
      missing_ko+=("$file -> $ko")
    fi
  fi
done < <(find "$ROOT" -type f -name "*.md" -print0)

status=0

if [[ ${#missing_ko[@]} -gt 0 ]]; then
  echo "Missing Korean translations (${#missing_ko[@]}):"
  printf '  %s\n' "${missing_ko[@]}"
  status=1
fi

if [[ ${#missing_en[@]} -gt 0 ]]; then
  echo "Missing English originals (${#missing_en[@]}):"
  printf '  %s\n' "${missing_en[@]}"
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Doc parity OK: every page has both EN and KO."
fi

exit $status
