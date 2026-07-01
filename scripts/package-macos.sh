#!/usr/bin/env bash
# Bundle Homebrew-linked dylibs next to a Crystal macOS binary so the
# release tarball runs without a local OpenSSL (or other brew) install.
#
# Usage: scripts/package-macos.sh <binary-path> <output-tarball>
#
# Archive layout:
#   noir
#   lib/*.dylib
set -euo pipefail

BINARY="${1:?Usage: $0 <binary-path> <output-tarball>}"
OUTPUT="${2:?Usage: $0 <binary-path> <output-tarball>}"

if [[ ! -f "$BINARY" ]]; then
  echo "error: binary not found: $BINARY" >&2
  exit 1
fi

if ! command -v otool >/dev/null 2>&1 || ! command -v install_name_tool >/dev/null 2>&1; then
  echo "error: otool and install_name_tool are required (macOS only)" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/lib"
cp "$BINARY" "$STAGING/noir"
chmod +x "$STAGING/noir"

# Homebrew prefixes on Apple Silicon and Intel Macs.
BREW_PREFIX_RE='^(/opt/homebrew|/usr/local)/'

homebrew_deps() {
  local target="$1"
  otool -L "$target" | awk 'NR>1 {print $1}' | grep -E "$BREW_PREFIX_RE" || true
}

DEPS_FILE="$STAGING/deps.txt"
: > "$DEPS_FILE"

# Collect transitive Homebrew dylibs (e.g. libssl -> libcrypto).
# Record every absolute load path (Cellar vs opt symlinks) but copy once per basename.
while true; do
  added=0
  for target in "$STAGING/noir" "$STAGING"/lib/*.dylib; do
    [[ -e "$target" ]] || continue
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      base="$(basename "$dep")"
      if ! grep -Fxq "$dep" "$DEPS_FILE"; then
        echo "$dep" >> "$DEPS_FILE"
      fi
      if [[ ! -f "$STAGING/lib/$base" ]]; then
        cp "$dep" "$STAGING/lib/$base"
        added=1
      fi
    done < <(homebrew_deps "$target")
  done
  [[ "$added" -eq 0 ]] && break
done

rewrite_paths() {
  local target="$1"
  local linked
  linked="$(otool -L "$target" | awk 'NR>1 {print $1}')"
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    echo "$linked" | grep -Fxq "$dep" || continue
    install_name_tool -change "$dep" "@executable_path/lib/$(basename "$dep")" "$target"
  done < "$DEPS_FILE"
}

rewrite_paths "$STAGING/noir"
for lib in "$STAGING"/lib/*.dylib; do
  [[ -e "$lib" ]] || continue
  install_name_tool -id "@executable_path/lib/$(basename "$lib")" "$lib"
  rewrite_paths "$lib"
done

for candidate in "$STAGING/noir" "$STAGING"/lib/*.dylib; do
  [[ -e "$candidate" ]] || continue
  if otool -L "$candidate" | awk 'NR>1 {print $1}' | grep -Eq "$BREW_PREFIX_RE"; then
    echo "error: Homebrew paths remain after bundling in $candidate:" >&2
    otool -L "$candidate" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$OUTPUT")"
tar -czf "$OUTPUT" -C "$STAGING" noir lib

echo "Created $OUTPUT"
if "$STAGING/noir" --version >/dev/null 2>&1; then
  "$STAGING/noir" --version
fi