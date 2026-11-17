# Blog post covers

Each post under `docs/content/blog/<slug>/` can carry a `cover.webp`. The blog
index, the author pages and the post itself show it when the post's front
matter has `cover = "cover.webp"` (set it in both `index.md` and
`index.ko.md`; the one file serves both languages).

`cover.html` is the layout: a Hak mascot from `docs/static/images/mascot/` on a
blind-lit plate, beside one to three lines of text in Geist Mono. The text is
a command, a flag or a name from the post, never the post title, so the cover
needs no translation. `build.sh` screenshots the page with headless Chrome at
1600x840 and encodes it with `cwebp`.

## Render a cover

```bash
docs/tools/blog-cover/build.sh <slug> <mood> <line> [line] [line]
```

`mood` is the `<mood>` in `hak-<mood>.webp`. In a line, a `[bracketed]` run is
set in the dim ink and the rest in the bright one. Long lines shrink to fit.

Requirements: `bash`, `python3`, Google Chrome (or set
`CHROME=/path/to/chrome`), and `cwebp`.

## The existing covers

```bash
B=docs/tools/blog-cover/build.sh
$B welcome-to-the-noir-blog     wave    '[noir ]blog'
$B noir-v1-release              good    '[noir ]v1.0'
$B ai-context-and-callee-hints  idea    '[--]ai-context' '[--include ]callee'
$B introducing-alibi            inspect '[owasp-noir/]' 'alibi'
$B pvalue-for-runnable-catalogs dev     '[--]pvalue' '[TYPE=]VALUE'
$B query-reach-trace            map     '[noir ]query' '[noir ]reach' '[noir ]trace'
```
