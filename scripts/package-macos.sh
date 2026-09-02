#!/usr/bin/env bash
# Bundle Homebrew-linked dylibs next to a Crystal macOS binary so the
# release tarball runs without a local OpenSSL (or other brew) install.
#
# Rewriting load commands with install_name_tool invalidates a Mach-O code
# signature. The linker-signed main binary gets re-signed automatically, but
# Homebrew's plainly ad-hoc-signed dylibs do not: they are left with a stale
# signature, and arm64 SIGKILLs any process that maps one. So everything is
# re-signed ad hoc after the last install_name_tool call, and the packaged
# tarball is smoke-tested before the script reports success.
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

for tool in otool install_name_tool codesign; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool is required (macOS only)" >&2
    exit 1
  fi
done

STAGING="$(mktemp -d)"
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING" "$VERIFY_DIR"' EXIT

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
        # Homebrew ships dylibs read-only; install_name_tool and codesign
        # both rewrite them in place.
        chmod u+w "$STAGING/lib/$base"
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

# Re-sign ad hoc. This must come after every install_name_tool call above,
# and dylibs must be signed before the binary that loads them.
for lib in "$STAGING"/lib/*.dylib; do
  [[ -e "$lib" ]] || continue
  codesign --force --sign - "$lib"
done
codesign --force --sign - "$STAGING/noir"

for target in "$STAGING/noir" "$STAGING"/lib/*.dylib; do
  [[ -e "$target" ]] || continue
  if ! codesign --verify --strict "$target"; then
    echo "error: invalid code signature after packaging: $target" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$OUTPUT")"
tar -czf "$OUTPUT" -C "$STAGING" noir lib

# Smoke-test the packaged artifact rather than the staged tree: this is the
# exact layout a user unpacks, and a stale signature is fatal only at exec
# time. Guarding this behind `if` hid exactly the breakage it existed to catch.
tar -xzf "$OUTPUT" -C "$VERIFY_DIR"
smoke_status=0
VERSION_OUTPUT="$("$VERIFY_DIR/noir" --version)" || smoke_status=$?
if [[ "$smoke_status" -ne 0 ]]; then
  echo "error: packaged binary failed to run (exit $smoke_status): $OUTPUT" >&2
  echo "       arm64 SIGKILLs binaries and dylibs with an invalid signature;" >&2
  echo "       check the codesign step above." >&2
  exit 1
fi

echo "Created $OUTPUT"
echo "$VERSION_OUTPUT"
