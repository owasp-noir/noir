# README hero image

`docs/content/get_started/overview/noir-usage.jpg` is the image the README and
the overview page embed. Like the CLI screenshots in `../cli-capture/`, the
terminal in it is a **real capture** of a real `noir scan ./demo-app -P -T`
run, not a mock-up: `build.sh` runs the built binary against
`../cli-capture/demo-app` on a PTY under a throwaway `NOIR_HOME`, `hero.py`
lays the transcript out next to the demo app's source and a JSON excerpt, and
headless Chrome renders the page at 2x before ImageMagick encodes the JPG.

The source and JSON panels are typed by hand in `hero.py` so they stay short
enough to read at README width. Keep them in sync with `demo-app/src/app.cr`
and with what the terminal panel shows.

## Regenerate

```bash
just docs-hero          # builds ./bin/noir, then runs build.sh
```

Or against a binary you already have:

```bash
docs/tools/readme-hero/build.sh [path-to-noir-binary]
```

Requirements: `bash`, `python3`, `script(1)`, Google Chrome (or set
`CHROME=/path/to/chrome`), and ImageMagick (`magick`).

The elapsed time in `Scan completed in ...` and the passive rule count vary
between runs, so the JPG is never byte-identical. Eyeball it before committing.
