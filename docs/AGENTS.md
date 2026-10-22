# AGENTS.md - AI Agent Instructions for Hwaro Site

This document provides instructions for AI agents working on this Hwaro-generated website.

## Project Overview

This is a static website built with [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator written in Crystal.

## Essential Commands

| Command | Description |
|---------|-------------|
| `hwaro build` | Build the site to `public/` directory |
| `hwaro serve` | Start development server with live reload |
| `hwaro new <path>` | Create new content from archetype |
| `hwaro deploy` | Deploy the site (requires configuration) |
| `hwaro build --drafts` | Include draft content |
| `hwaro serve -p 8080` | Serve on custom port (default: 3000) |
| `hwaro build --base-url "https://example.com"` | Set base URL for production |

## Directory Structure

```
.
├── config.toml          # Site configuration
├── content/             # Markdown content files
│   ├── index.md         # Homepage (single file, no underscore)
│   ├── about.md         # Standalone page
│   └── <section>/       # Section directory (posts/, guide/, chapter-1/, …)
│       ├── _index.md    # Section landing page (underscore-prefixed)
│       └── *.md         # Pages within the section
├── templates/           # Jinja2 templates (Crinja)
│   ├── header.html      # Shared <head> + <body> open
│   ├── footer.html      # Shared <body>/<html> close
│   ├── page.html        # Page template
│   ├── section.html     # Section listing template
│   ├── 404.html         # Not-found page
│   ├── partials/        # Reusable fragments (nav, search, sidebar)
│   └── shortcodes/      # Shortcode templates
├── static/              # Static assets (copied as-is)
└── archetypes/          # Content templates for `hwaro new`
```

## Notes for AI Agents

1. **Front matter** can be TOML (`+++`), YAML (`---`), or JSON (`{...}` at file start). Pick one per file and keep delimiters matched.
2. **Rendered content** is `{{ content }}` in templates (already-safe HTML — no extra `| safe` needed).
3. **Custom metadata** is `page.extra.field`, not `page.params.field`.
4. **Always preview** with `hwaro serve` before committing.
5. **Validate front matter syntax** (TOML, YAML, or JSON) and `config.toml` after edits.
6. **Use `{{ base_url }}` prefix** for URLs in templates.
7. **Escape user content** with `{{ value | e }}` (or `| escape`) in templates.

## Full Reference

For detailed documentation on content, templates, configuration, and more:

- [Hwaro Documentation](https://hwaro.hahwul.com)
- [Configuration Guide](https://hwaro.hahwul.com/start/config/)
- [Full LLM Reference](https://hwaro.hahwul.com/llms-full.txt) — comprehensive reference optimized for AI agents

To generate the full embedded AGENTS.md locally, run:
```
hwaro tool agents-md --local --write
```

## Site-Specific Instructions

### Design contract

The visual language is cinematic monochrome with exactly one accent: a signal
red sampled from the red crest of Hak, the mascot. Before changing anything
visual, read the header comment in `static/css/style.css`.

- **One accent.** `--accent` is the only hue on the site, apart from `--warn`,
  which is reserved for warning callouts. Do not introduce a second colour, and
  do not spend the accent on decoration. It marks links, the active nav item,
  the active TOC entry, and the primary CTA. Nothing else. Third-party logos are
  grayscaled precisely so Hwaro's brick red cannot leak in.
- **Contrast is measured, not guessed.** `--accent` on a red fill takes
  `--accent-ink` (near-black) because white-on-red is 3.58:1 and fails AA. Body
  links use `--accent-text`, never raw `--accent`, which drops below 4.5:1 on
  `--surface`. `--text-muted` is already at its dim floor: dimming it further
  fails the small labels that use it.
- **One radius scale.** `--r` everywhere, `--r-lg` on large panels, `0` on
  full-bleed media. Nothing is a pill.
- **Every z-index comes from the scale** at the top of `style.css`. No bare
  integers.
- **No em-dashes in newly authored copy.** Use a period, a comma, or a colon.
  (Some older ported pages still contain them.)

### Traps that have already bitten

- **Blank lines inside raw HTML in Markdown.** CommonMark ends an HTML block at
  the first blank line; the next line, if indented 4+ spaces, becomes an
  *indented code block*. `content/_index.md` therefore has no blank lines inside
  a `<section>`. Sections are separated by one blank line and start at column
  zero.
- **A `::after` pseudo-element paints above its siblings**, including a
  positioned `.cell-body`. The bento texture tile layers its image and its scrim
  into a single `::before` for exactly this reason.
- **The landing hero needs `.landing` on `<main>`.** That class pulls the hero
  up under the sticky header. Without it the bar sits on the page background and
  its bone ink lands on white in light mode.
- **The header is transparent only at scroll position zero.** `.hero-sentinel`
  is a 1px marker at the header's bottom edge; `nav.js` watches it and gives the
  bar its background the moment anything scrolls beneath it. Tying that to the
  end of the hero instead lets hero copy slide through a transparent bar and
  tangle with the nav links.
- **Fade screenshots into their own background (`--shot-bg`), never to
  transparent.** Masking to transparent lets a white card show through a dark
  terminal capture, which reads as a haze across the bottom of the image in
  light mode.
- **Never close `@media (max-width: 900px)` early.** That block holds both the
  header collapse AND the sidebar drawer. Closing it after the header rules
  parks `position: fixed; transform: translateX(-102%)` at top level, and the
  sidebar vanishes off-screen at *every* width while still passing a contrast
  or overflow check (the elements exist, they are just off-canvas). Braces stay
  balanced; add new breakpoints *after* the block, not inside it.
- **`hwaro serve`'s FIRST build uses `base_url` from `config.toml`;** only
  incrementally re-rendered pages get the serve address. So the landing may look
  fine while every other page loads no CSS. Always start it explicitly:
  `hwaro serve -p 3100 --base-url "http://127.0.0.1:3100"`. Never run
  `hwaro build` against `public/` while `serve` is running.
- **`{{ ... }}` inside a `{# ... #}` comment is still parsed** and will fail the
  build. Refer to template variables by name in comments, without braces.
- **`{{ highlight_js }}` / `{{ highlight_css }}` emit root-absolute `/assets/`
  paths** that ignore `base_url` and 404 under the `/noir` sub-path. Both are
  referenced manually via `{{ base_url }}`; the builds are vendored under
  `static/assets/`.
- **Custom front matter must be flat scalars.** Inline TOML sub-tables do not
  surface. Use `prev_page_path` / `prev_page_label`, read via `page.extra.*`.
- **The TOC comes from `toc = true`,** set once per section through
  `[cascade]` in each `_index.md`. A page with no `h2`/`h3` correctly renders no
  TOC.

### Bilingual site

Every page exists in English and Korean. `scripts/check_doc_parity.sh` is a CI
gate: adding `foo.md` without `foo.ko.md` (or the reverse) fails the build,
because the language switcher would point at a 404.

- **UI strings live in `i18n/en.toml` and `i18n/ko.toml`,** referenced as
  `{{ "sidebar.first_scan" | t }}`. Never inline a `{% if page_language == "ko" %}`
  for copy. An **unresolved key silently renders the key itself** (you get a
  literal `ui.language` in the page), so after editing templates, grep the built
  HTML for `\b(ui|nav|sidebar|footer|blog|authors|notfound)\.[a-z_]+\b`.
- **Links are language-neutral plus `lang_prefix`.** Write
  `{{ base_url }}{{ lang_prefix }}/usage/`. `page.url` already carries the
  prefix, so a current-page test must compare against `lang_prefix ~ href`.
- **`toc = true` is set per section via `[cascade]`,** which means it must be
  added to **both** `_index.md` and `_index.ko.md`. Miss the Korean one and
  every Korean page loses its table of contents.
- **The Korean landing lives at `/ko/`,** so its images go up a level
  (`../images/...`) while its document links stay put (`./get_started/...`).
- `site.extra` is **not** exposed to templates. The version chip is a literal in
  `templates/partials/nav.html`; `scripts/version_update.cr` rewrites it there.

### Conventions

- `templates/partials/sidebar.html` is hand-authored. **Every page must appear
  in it exactly once.** The previous site stranded four pages that existed but
  were unreachable from the nav. If you add a page, add it to the sidebar.
- Icons come from the sprite in `templates/partials/icons.html`, vendored from
  Tabler Icons (MIT). Do not hand-write SVG paths; re-vendor from the package.
- Motion is native CSS plus IntersectionObserver. `window.addEventListener("scroll", ...)`
  is banned. Everything collapses under `prefers-reduced-motion: reduce`.
- Nothing is hidden unless `:root.js` is present, so a page whose scripts fail
  to load is still fully readable.

### Checking your work

```
bash docs/scripts/check_doc_parity.sh            # CI gate: EN/KO parity
(cd docs && hwaro build)
bash docs/scripts/check_edit_links.sh            # every "Edit this page" target exists
cd docs
hwaro doctor && hwaro tool validate && hwaro tool check-links
hwaro serve -p 3100 --base-url "http://127.0.0.1:3100"
hwaro build --base-url "https://owasp-noir.github.io/noir"   # sub-path check
```

Two more traps worth knowing:

- **hwaro exposes no source-file path.** `page.path`, `page.file`, `page.source`
  and friends are all empty, so `page.html` and `section.html` rebuild the edit
  link from `page.url` plus the page language. `check_edit_links.sh` is what
  keeps that derivation honest.
- **`.prose pre` also matches `<pre class="mermaid">`.** Any script that styles
  or decorates code blocks must use `.prose pre:not(.mermaid)`, or every diagram
  gains a "CODE" label and a Copy button that copies SVG node labels.

Look at the result in **both** themes and at 390px before calling it done.