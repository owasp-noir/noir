#!/usr/bin/env bash
#
# build.sh: render a blog post cover into the post's page bundle
# (docs/content/blog/<slug>/cover.webp).
#
# cover.html lays out a Hak mascot from docs/static/images/mascot over a
# blind-lit plate, next to one to three lines of text. Headless Chrome
# screenshots it at 1600x840 and cwebp encodes it.
#
# Requirements: bash, python3, Google Chrome, cwebp.
# Usage:  docs/tools/blog-cover/build.sh <slug> <mood> <line> [line] [line]
#   mood  the <mood> in docs/static/images/mascot/hak-<mood>.webp
#   line  text; a [bracketed] run is set in the dim ink
set -euo pipefail

[ $# -ge 3 ] || { sed -n '/^# Usage/,/^set/p' "$0" | sed '$d'; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SLUG="$1"; MOOD="$2"; shift 2
OUT="$REPO/docs/content/blog/$SLUG/cover.webp"

[ -d "$(dirname "$OUT")" ] || { echo "no such post: docs/content/blog/$SLUG"; exit 1; }
[ -f "$REPO/docs/static/images/mascot/hak-$MOOD.webp" ] || { echo "no such mood: $MOOD"; exit 1; }
command -v cwebp >/dev/null || { echo "cwebp is required"; exit 1; }

CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome chromium chromium-browser; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then CHROME="$c"; break; fi
  done
fi
[ -n "$CHROME" ] || { echo "Chrome not found; set CHROME=/path/to/chrome"; exit 1; }

QUERY="$(python3 -c 'import sys, urllib.parse as u; print(u.urlencode([("mood", sys.argv[1])] + [("l", l) for l in sys.argv[2:]]))' "$MOOD" "$@")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The headless window is shorter than --window-size by the height of the
# browser chrome it does not draw, so ask for more and crop to the plate.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1600,1100 \
  --allow-file-access-from-files --virtual-time-budget=3000 \
  --screenshot="$WORK/cover.png" "file://$HERE/cover.html?$QUERY" >/dev/null 2>&1
cwebp -quiet -q 82 -crop 0 0 1600 840 "$WORK/cover.png" -o "$OUT"
echo "wrote ${OUT#"$REPO"/} ($(wc -c < "$OUT" | tr -d ' ') bytes)"
