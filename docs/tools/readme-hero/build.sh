#!/usr/bin/env bash
#
# build.sh: regenerate the hero image the README and the overview page embed
# (docs/content/get_started/overview/noir-usage.jpg).
#
# The terminal panel is the --no-log view (results only) so the image stays
# wide rather than tall.
#
# Runs the built ./bin/noir against docs/tools/cli-capture/demo-app on a PTY
# (same staging and throwaway NOIR_HOME as cli-capture/capture.sh), lays the
# transcript out with hero.py, screenshots the page with headless Chrome at
# 2x, and encodes the JPG with ImageMagick.
#
# Requirements: bash, python3, script(1), Google Chrome, ImageMagick (magick),
# and a built ./bin/noir. macOS and Linux.
# Usage:  docs/tools/readme-hero/build.sh [path-to-noir-binary]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
NOIR="${1:-$REPO/bin/noir}"
OUT="$REPO/docs/content/get_started/overview/noir-usage.jpg"
DEMO="$REPO/docs/tools/cli-capture/demo-app"

[ -x "$NOIR" ] || { echo "noir binary not found/executable at $NOIR (run 'just build-release' first)"; exit 1; }
command -v magick >/dev/null || { echo "ImageMagick (magick) is required"; exit 1; }

CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome chromium chromium-browser; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then CHROME="$c"; break; fi
  done
fi
[ -n "$CHROME" ] || { echo "Chrome not found; set CHROME=/path/to/chrome"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export NOIR_HOME="$WORK/home"
mkdir -p "$NOIR_HOME"

STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R "$DEMO" "$STAGE/demo-app"
mkdir -p "$STAGE/demo-app/config"
cp "$REPO/spec/functional_test/fixtures/etc/passive_scan/private_key.pem" \
   "$STAGE/demo-app/config/private_key.pem"

# script(1) forwards the child's exit status but has been seen to report
# failure on a run that produced a full transcript; the length check below is
# what guards against an empty frame.
REC="$WORK/scan.ansi"
if [ "$(uname)" = "Darwin" ]; then
  (cd "$STAGE" && TERM=xterm-256color script -q "$REC" "$NOIR" scan ./demo-app -P -T --no-log --no-spinner >/dev/null 2>&1 || true)
else
  (cd "$STAGE" && SHELL=/bin/bash TERM=xterm-256color script -qec "$(printf '%q ' "$NOIR" scan ./demo-app -P -T --no-log --no-spinner)" "$REC" >/dev/null 2>&1 || true)
fi

python3 - "$REC" "$NOIR_HOME" <<'PY'
import sys
p, home = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8", errors="replace").read()
t = t.replace(home, "~/.config/noir")
if home in t or "/tmp." in t or "/var/folders/" in t:
    sys.exit(f"temp home leaked into the capture and could not be scrubbed: {home}")
if len([ln for ln in t.splitlines() if ln.strip()]) < 10:
    sys.exit("capture produced almost no output; refusing to overwrite the image")
open(p, "w", encoding="utf-8").write(t)
PY

python3 "$HERE/hero.py" "$REC" "$WORK/hero.html"
# Headless Chrome sometimes exits non-zero after a successful capture, so the
# screenshot file, not the exit status, decides.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1800,830 \
  --force-device-scale-factor=2 --screenshot="$WORK/hero.png" "file://$WORK/hero.html" >/dev/null 2>&1 || true
[ -s "$WORK/hero.png" ] || { echo "Chrome produced no screenshot"; exit 1; }
magick "$WORK/hero.png" -quality 86 -sampling-factor 4:2:0 -strip -interlace JPEG "$OUT"
echo "▸ wrote $OUT ($(magick identify -format '%wx%h' "$OUT"))"
