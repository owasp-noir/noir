#!/bin/sh
# Build script invoked from tree_sitter.cr's @[Link(ldflags: ...)] annotation.
#
# This script has three jobs:
#   1. Compile the vendored tree-sitter runtime (runtime/src/lib.c, a unity
#      build that `#include`s every other runtime .c file) into a single
#      object. WASM support is deliberately disabled so the runtime has
#      zero external dependencies.
#   2. Compile each vendored grammar's parser.c and scanner.c (stale-check).
#   3. Emit the object file paths on stdout so the Crystal linker pulls
#      them directly into the noir binary — no -ltree-sitter, no system
#      library required at build or runtime.
#
# Anything human-readable goes to stderr so it stays out of the ldflags.

set -eu
D="$(cd "$(dirname "$0")" && pwd)"
CC_BIN="${CC:-cc}"

# --- Compile the tree-sitter runtime once --------------------------------
RUNTIME_SRC="$D/runtime/src/lib.c"
RUNTIME_OBJ="$D/runtime/lib.o"
RUNTIME_INCLUDE="-I$D/runtime/include -I$D/runtime/src"

# Detect whether any runtime source/header is newer than the object.
runtime_stale=0
if [ ! -f "$RUNTIME_OBJ" ]; then
  runtime_stale=1
else
  for f in "$D"/runtime/src/*.c "$D"/runtime/src/*.h \
           "$D"/runtime/src/portable/*.h "$D"/runtime/src/unicode/*.h \
           "$D"/runtime/include/tree_sitter/api.h; do
    [ -f "$f" ] || continue
    if [ "$f" -nt "$RUNTIME_OBJ" ]; then
      runtime_stale=1
      break
    fi
  done
fi

if [ "$runtime_stale" -eq 1 ]; then
  echo "[noir/tree-sitter] building runtime lib.o (vendored)" 1>&2
  # -O2 matches upstream defaults; -fvisibility=hidden keeps runtime
  # symbols out of noir's exported surface. No -DTREE_SITTER_FEATURE_WASM
  # so wasm_store.c collapses to an empty TU. -D_DEFAULT_SOURCE exposes
  # glibc's le16toh/be16toh/fdopen — tree-sitter's portable/endian.h
  # reaches for these on Linux and `-std=c11` alone hides them behind
  # __STRICT_ANSI__.
  # shellcheck disable=SC2086
  $CC_BIN -c -O2 -fPIC -std=c11 -fvisibility=hidden \
    -D_DEFAULT_SOURCE \
    $RUNTIME_INCLUDE \
    -o "$RUNTIME_OBJ" "$RUNTIME_SRC" 1>&2
fi

# --- Compile grammars ----------------------------------------------------
# Each grammar ships `parser.c` (always, auto-generated). Most also ship
# `scanner.c` (hand-written custom lexer for context-sensitive tokens) —
# Go does not, so we compile scanner.c only when the file exists.
GRAMMARS="python go"
OBJS="$RUNTIME_OBJ"
for g in $GRAMMARS; do
  GD="$D/grammars/$g"
  for src in parser scanner; do
    SRC="$GD/$src.c"
    OBJ="$GD/$src.o"
    [ -f "$SRC" ] || continue
    if [ ! -f "$OBJ" ] \
      || [ "$SRC" -nt "$OBJ" ] \
      || [ "$GD/tree_sitter/parser.h" -nt "$OBJ" ]; then
      echo "[noir/tree-sitter] building $g/$src.o" 1>&2
      # Grammars only need the runtime's public api.h, not the private
      # headers, so we pass just the include dir (not the src dir).
      # shellcheck disable=SC2086
      $CC_BIN -c -O2 -fPIC -I"$GD" -I"$D/runtime/include" \
        -o "$OBJ" "$SRC" 1>&2
    fi
    OBJS="$OBJS $OBJ"
  done
done

printf '%s' "$OBJS"
