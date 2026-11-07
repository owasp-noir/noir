#!/bin/sh
# Run a compile while holding one of a few machine-wide slots.
#
# A compile of noir is memory-bound, not CPU-bound: the spec suite peaks at
# ~11GB RSS and src/noir.cr at ~6GB, and `--threads` barely moves either. So
# three worktrees compiling at once push a 36GB machine into swap, and every
# build slows down together. Queueing behind a slot finishes sooner.
#
#   scripts/compile_gate.sh crystal build spec/suite.cr -o bin/noir_spec
#
# NOIR_COMPILE_SLOTS sets the slot count (default 2; 0 disables the gate).
# Slots live under $TMPDIR, so every worktree of the same user shares them.
# A slot whose holder died is reclaimed by the next waiter.
#
# ponytail: mkdir-based semaphore (macOS ships no flock). Two waiters reaping
# the same dead slot can race and let one extra compile through; harmless.
set -eu

slots="${NOIR_COMPILE_SLOTS:-2}"
[ "$slots" -gt 0 ] || exec "$@"

dir="${TMPDIR:-/tmp}/noir-compile-gate"
mkdir -p "$dir"

held=""
announced=0
while [ -z "$held" ]; do
  i=0
  while [ "$i" -lt "$slots" ]; do
    slot="$dir/slot$i"
    if mkdir "$slot" 2>/dev/null; then
      echo $$ > "$slot/pid"
      held="$slot"
      break
    fi
    pid=$(cat "$slot/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$slot"
      continue
    fi
    i=$((i + 1))
  done
  if [ -z "$held" ]; then
    if [ "$announced" -eq 0 ]; then
      echo "[compile-gate] $slots compile(s) already running; waiting (NOIR_COMPILE_SLOTS=$slots)" 1>&2
      announced=1
    fi
    sleep 1
  fi
done

trap 'rm -rf "$held"' EXIT
trap 'exit 130' INT TERM
"$@"
