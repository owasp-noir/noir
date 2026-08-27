# CLI screenshots

The terminal screenshots in the docs are **real captures** of a real `noir`
run, not hand-drawn mock-ups or hand-edited window art. They are rendered to
self-contained SVG, so they stay crisp at any size, weigh ~30 KB instead of the
300 KB a PNG of the same frame costs, and are diffable text in review.

## How it works

1. `capture.sh` runs the binary against `demo-app/` (the small Kemal app in
   this directory) on a real PTY via `script(1)`, so noir sees a terminal and
   colors its output the way a reader's own run would. The transcript is
   captured as truecolor ANSI.
2. `ansi2svg.py` parses that ANSI into a cell grid and emits an SVG, placing
   each run of text with `textLength` + `lengthAdjust` so the monospace grid
   stays aligned regardless of the viewer's font.

Everything the scan reads lives under a throwaway `NOIR_HOME` from
`mktemp -d`, and nothing is read out of your real `~/.config/noir`. That
includes the passive rules: noir clones the upstream ruleset into the
throwaway home on the first `-P` scene, so the rule count and the findings in
a published image come from upstream rather than from whatever the person
regenerating happens to have installed locally. That one path needs network
and git.

`demo-app/` itself is staged into that temp directory before each run rather
than scanned in place. That is where the private key the `-P` scene finds
comes from: `capture.sh` copies in the one the passive-scan specs already use
(`spec/functional_test/fixtures/etc/passive_scan/private_key.pem`) instead of
the repo carrying a second copy of a key. Everything else in the staged tree
is exactly what is checked in here.

The renderer targets a dark terminal: cells the transcript leaves unstyled are
painted with `RESET_FG` on `RESET_BG` in `ansi2svg.py`, because a terminal
emits no escape at all for its own default colors and there is nothing in a
transcript to infer them from. Capturing from a light-theme terminal gives you
that theme's *explicit* colors on a dark frame, which is not what you want;
change the two constants if the docs ever need a light set.

## Regenerate

```bash
just docs-capture          # builds ./bin/noir, then runs capture.sh
```

Or directly, against a binary you already have:

```bash
docs/tools/cli-capture/capture.sh [path-to-noir-binary]
```

Requirements: `bash`, `python3`, `script(1)` (BSD and util-linux both work),
and a built `./bin/noir`.

Captures are reproducible but not byte-identical run to run: the elapsed time
in `Scan completed in ...` varies, and the passive rule count follows whatever
`noir-passive-rules` currently ships. Eyeball the output before committing.
`git diff` on the SVG shows exactly which cells moved.

## Add a scene

One line in `capture.sh`:

```bash
shoot content/usage/output_formats/json/json-output.svg \
  "A terminal running noir scan -f json, printing the endpoint array." \
  scan ./demo-app -f json
```

The first argument is the SVG's path under `docs/`. Images live next to the
page that shows them, which is the convention in `docs/content/`, so the path
names the page directory. The second is the alt text and should say what is on
screen. Everything after is passed to `noir` verbatim, becomes the
`$ noir ...` prompt line at the top of the frame, and becomes the window
title.

`capture.sh` prints the `<img>` tag for each scene it renders, with the alt
text and the dimensions that render actually produced. Paste it into both
language variants of the page rather than hand-copying four values:

```html
<img src="./json-output.svg" alt="..." width="639" height="1258" loading="lazy" decoding="async">
```

Three things to keep in mind when the scene needs its own input:

- **Paths in the output are the paths in the image.** Scenes run with the
  staging directory as their working directory, so `./demo-app` renders as
  `demo-app/src/app.cr`, a path that doesn't depend on where the repo is
  checked out. Point a scene at a fixture elsewhere in the repo and the image
  grows an absolute path; stage what the scene needs instead. `capture.sh`
  refuses to write an SVG that still contains the temp path.
- **`demo-app/` is a published surface.** Every route in it is there to put
  one specific thing on screen: a header, a cookie, a websocket route, and
  body params that earn a tag. The tags are the fragile part, since they come
  from verbatim word lists in `src/tagger/taggers/hunt_param.cr`. Renaming
  `search` or `redirect_url` to something that reads better silently drops its
  tag from the screenshot.
- **Redraws don't survive the render.** `ansi2svg.py` replays SGR colors,
  carriage return, backspace and tab, but drops cursor motion and
  erase-in-line. Anything that rewrites a line in place renders with the old
  text still showing, which is why every scene passes `--no-spinner`.

## Render a single frame by hand

```bash
script -q frame.ansi noir scan ./demo-app --no-spinner
python3 ansi2svg.py frame.ansi frame.svg --title "noir scan ./demo-app"
```
