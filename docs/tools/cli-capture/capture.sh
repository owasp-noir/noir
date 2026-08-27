#!/usr/bin/env bash
#
# capture.sh: regenerate the CLI screenshots the docs embed.
#
# It runs a real noir binary against the demo app in this directory on a PTY
# (script(1)) so noir colors its output, then renders the ANSI transcript to a
# self-contained SVG with ansi2svg.py.
#
# Everything the scan reads is under a throwaway NOIR_HOME from mktemp -d, and
# nothing is read out of your real ~/.config/noir. That includes the passive
# rules: noir clones the upstream ruleset into the throwaway home on the first
# -P scene, so the rule count and findings in a published image come from
# upstream rather than from whatever the person regenerating happens to have
# installed. That one path needs network and git.
#
# Requirements: bash, python3, script(1) (BSD and util-linux both work), and
# a built ./bin/noir.
# Usage:  docs/tools/cli-capture/capture.sh [path-to-noir-binary]
#
# Captures are reproducible but not byte-identical run to run: the elapsed
# time in "Scan completed in ..." varies, and the passive rule count follows
# whatever upstream ships. Eyeball the output before committing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
NOIR="${1:-$REPO/bin/noir}"

[ -x "$NOIR" ] || { echo "noir binary not found/executable at $NOIR (run 'just build-release' first)"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export NOIR_HOME="$WORK/home"
mkdir -p "$NOIR_HOME"

# Scans run against a staged copy of demo-app, not the checked-in one, so the
# passive scanner has a secret to find without the repo carrying a second
# private key: the one the passive-scan specs already use is copied in here.
# Staging keeps the rendered paths identical either way. Every scene runs with
# $STAGE as its working directory, so `./demo-app` renders as
# `demo-app/src/app.cr` and never leaks where the repo is checked out.
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R "$HERE/demo-app" "$STAGE/demo-app"
mkdir -p "$STAGE/demo-app/config"
cp "$REPO/spec/functional_test/fixtures/etc/passive_scan/private_key.pem" \
   "$STAGE/demo-app/config/private_key.pem"

# run_pty <ansi-out> <argv...>: run argv on a real PTY (so noir sees a
# terminal and colors both streams) and record the full ANSI transcript.
# script(1) creates the transcript whether or not the child succeeds, so the
# child's own status is what decides; without propagating it, a crashed noir
# would quietly overwrite a committed SVG with an empty frame.
run_pty() {
  local rec="$1"; shift
  if [ "$(uname)" = "Darwin" ]; then
    # BSD script: script [-q] file command ...
    (cd "$STAGE" && TERM=xterm-256color script -q "$rec" "$@" >/dev/null 2>&1)
  else
    # util-linux script: script -c "command" file, executed through $SHELL.
    # printf %q emits bash syntax, so pin $SHELL to bash rather than trusting
    # the login shell of whoever is regenerating (fish cannot parse $'...').
    local cmd
    cmd="$(printf '%q ' "$@")"
    (cd "$STAGE" && SHELL=/bin/bash TERM=xterm-256color script -qec "$cmd" "$rec" >/dev/null 2>&1)
  fi
}

# shoot <out-svg-under-docs/> <aria> <noir-args...>: record `noir <args>
# --no-spinner`, prefix the frame with the "$ noir <args>" prompt line a
# reader would type (--no-spinner only keeps spinner frames out of the
# recording; the visible output is identical), scrub the throwaway home path,
# and render the SVG. Images live next to the docs page that shows them (the
# repo's colocated-image convention), so the out path names the page dir.
shoot() {
  local out="$REPO/docs/$1" aria="$2"; shift 2
  local name
  name="$(basename "${out%.svg}")"
  echo "▸ capturing $name → $out"
  if ! run_pty "$WORK/$name.ansi" "$NOIR" "$@" --no-spinner; then
    echo "  noir exited non-zero; leaving $out untouched" >&2
    return 1
  fi
  python3 - "$WORK/$name.ansi" "$NOIR_HOME" <<'PY'
import sys
p, home = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8", errors="replace").read()
t = t.replace(home, "~/.config/noir")
# BSD script(1) echoes the EOF it sends the child as caret-notation noise
t = t.replace("^D\x08\x08", "").replace("\x04", "")
# The scrub above is a literal substring replace, and NOIR_HOME is mktemp -d
# output that embeds a per-user path. If noir ever prints it in a form the
# replace misses (resolved through /private on macOS, wrapped across a line),
# it would ship in a published image with nothing failing. Refuse instead.
if home in t or "/tmp." in t or "/var/folders/" in t:
    sys.exit(f"temp home leaked into the capture and could not be scrubbed: {home}")
# A crashed or flag-rejected run still leaves a transcript behind; a frame
# that short is never a real scene, and writing it would clobber the SVG.
if len([ln for ln in t.splitlines() if ln.strip()]) < 10:
    sys.exit("capture produced almost no output; refusing to overwrite the SVG")
open(p, "w", encoding="utf-8").write(t)
PY
  printf '\033[90m$\033[0m \033[1mnoir %s\033[0m\n\n' "$*" |
    cat - "$WORK/$name.ansi" > "$WORK/$name.full"
  mkdir -p "$(dirname "$out")"
  python3 "$HERE/ansi2svg.py" "$WORK/$name.full" "$out" \
    --title "noir $*" --aria "$aria" --fs 15
  # The <img> the page needs, with the dimensions this render actually
  # produced. The alt text has to match what is on screen and the width and
  # height have to match the frame, and both live in two language variants of
  # the page, so print the tag rather than leaving four values to hand-copy.
  python3 - "$out" "$aria" <<'PY'
import re, sys, html
out, aria = sys.argv[1], sys.argv[2]
svg = open(out, encoding="utf-8").read(400)
w, h = re.search(r'width="(\d+)" height="(\d+)"', svg).groups()
print(f'    <img src="./{out.rsplit("/", 1)[-1]}" alt="{html.escape(aria, quote=True)}" '
      f'width="{w}" height="{h}" loading="lazy" decoding="async">')
PY
}

# The first-scan hero (get_started/running): endpoints with headers, cookies,
# body params and tags, plus a passive private-key finding, out of the small
# Kemal app in demo-app/.
shoot content/get_started/running/scan.svg \
  "A terminal running noir scan with passive scanning and taggers enabled: five endpoints found with their parameters and tags, plus a critical private-key finding." \
  scan ./demo-app -P -T

echo "▸ done. Review the regenerated SVGs (git status shows what changed)."
