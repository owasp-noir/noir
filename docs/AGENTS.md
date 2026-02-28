# AGENTS.md - AI Agent Instructions for Hwaro Site

This document provides instructions for AI agents working on this Hwaro-generated website.

## Project Overview

This is a static website built with [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator written in Crystal.

## Hwaro Usage

### Installation

**Homebrew:**
```bash
brew tap hahwul/hwaro
brew install hwaro
```

**From Source (Crystal):**
```bash
git clone https://github.com/hahwul/hwaro.git
cd hwaro
shards install
shards build --release --no-debug --production
# Binary: ./bin/hwaro
```

### Essential Commands

| Command | Description |
|---------|-------------|
| `hwaro init [DIR]` | Initialize a new site |
| `hwaro build` | Build the site to `public/` directory |
| `hwaro serve` | Start development server with live reload |
| `hwaro version` | Show version information |
| `hwaro deploy` | Deploy the site (requires configuration) |

### Build & Serve Options

- **Drafts:** `hwaro build --drafts` / `hwaro serve --drafts` (Include content with `draft = true`)
- **Port:** `hwaro serve -p 8080` (Default: 3000)
- **Open:** `hwaro serve --open` (Open browser automatically)
- **Base URL:** `hwaro build --base-url "https://example.com"`

## Directory Structure

```
.
├── config.toml          # Site configuration
├── content/             # Markdown content files
│   ├── _index.md        # Homepage content
│   ├── about.md         # About page
│   └── blog/            # Blog section
│       ├── _index.md    # Blog listing page
│       └── *.md         # Individual blog posts
├── templates/           # Jinja2 templates (.html, .j2)
│   ├── header.html      # Site header partial
│   ├── footer.html      # Site footer partial
│   ├── page.html        # Default page template
│   ├── section.html     # Section listing template
│   └── 404.html         # Not found page
└── static/              # Static assets (copied as-is)
```

## Content Management

### Creating New Pages

Create a new `.md` file in the `content/` directory.

**Example Front Matter (TOML):**
```toml
+++
title = "Page Title"
date = "2024-01-01"
draft = false
tags = ["tag1", "tag2"]
+++

Your markdown content here.
```

### Creating Sections

1. Create a directory under `content/` (e.g., `content/projects/`)
2. Add `_index.md` for the section listing page
3. Add individual `.md` files for section items

**Section `_index.md` Example:**
```toml
+++
title = "Projects"
paginate = 10
pagination_enabled = true
sort_by = "date"   # "date" | "title" | "weight"
reverse = false
+++
```

### Front Matter Fields

| Field       | Type     | Description                              |
|-------------|----------|------------------------------------------|
| title       | string   | Page title (required)                    |
| date        | string   | Publication date (YYYY-MM-DD)            |
| draft       | boolean  | If true, excluded from production build  |
| description | string   | Page description for SEO                 |
| image       | string   | Featured image URL for social sharing    |
| tags        | array    | List of tags                             |
| categories  | array    | List of categories                       |
| template    | string   | Custom template name (without extension) |
| weight      | integer  | Sort order (lower = first)               |
| slug        | string   | Custom URL slug                          |
| aliases     | array    | URL redirects to this page               |

### Markdown Features

- **Standard Markdown:** Headers, lists, code blocks, etc.
- **Tables:** Supported.
- **Footnotes:** Supported.
- **Raw HTML:** Supported (unless `safe = true` in config).

## Template Development

### Template Location

All templates are in the `templates/` directory using Jinja2 syntax (powered by Crinja).

### Key Variables

#### Global Objects
- `site`: Site configuration and metadata (`site.title`, `site.base_url`).
- `page`: Current page object (available in page templates).
- `section`: Current section object (available in section templates).

#### Page Variables
Variables can be accessed via the `page` object:
- `{{ page.title }}` - Page title
- `{{ page.content }}` - Rendered content
- `{{ page.date }}` - Date object
- `{{ page.url }}` - Relative URL (e.g., `/blog/post/`)
- `{{ page.permalink }}` - Absolute URL
- `{{ page.section }}` - Section name
- `{{ page.params.custom_field }}` - Access extra front matter fields

### Common Jinja2 Syntax

- **Output:** `{{ variable }}`
- **Logic:** `{% if condition %}...{% endif %}`
- **Loops:** `{% for item in items %}...{% endfor %}`
- **Comments:** `{# comment #}`
- **Filters:** `{{ value | filter }}`

### Template Inheritance

**Base Template (`templates/base.html`):**
```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site.title }}{% endblock %}</title>
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

**Child Template (`templates/page.html`):**
```jinja
{% extends "base.html" %}

{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}

{% block content %}
  <article>
    <h1>{{ page.title }}</h1>
    {{ content }}
  </article>
{% endblock %}
```

### Partials

Include reusable components:
```jinja
{% include "header.html" %}
{% include "footer.html" %}
```

### Custom Filters

- `{{ date | date("%Y-%m-%d") }}` - Format date
- `{{ text | truncate_words(50) }}` - Truncate text
- `{{ text | slugify }}` - Convert to slug
- `{{ url | absolute_url }}` - Make URL absolute
- `{{ url | relative_url }}` - Prefix with base_url
- `{{ html | strip_html }}` - Remove HTML tags
- `{{ markdown | markdownify }}` - Render markdown

## Styling & Assets

### CSS Location
- Place CSS files in `static/css/`.
- Reference in templates: `<link rel="stylesheet" href="{{ base_url }}/css/style.css">`.

### Static Files
- Any file in `static/` is copied to the root of the output directory.
- Example: `static/robots.txt` -> `public/robots.txt`.

## Notes for AI Agents

1. **Always preserve front matter** when editing content files.
2. **Use `hwaro serve`** to preview changes.
3. **Check `config.toml`** for site-wide settings (e.g., markdown safety, pagination).
4. **Template Syntax:** Use standard Jinja2 syntax.
5. **Validate TOML syntax** in config.toml after edits.
6. **Keep URLs relative** using `{{ base_url }}` prefix where appropriate, or `page.url`.
7. **Escape user content** with `{{ value | escape }}` when needed.