+++
title = "HTML Report"
description = "Generate a comprehensive, visual HTML report of your attack surface scan results."
weight = 3
sort_by = "weight"

+++

Generate a self-contained, interactive HTML file that visualizes scan results. The report ships a redesigned, monochrome "noir" theme — a single file with no external dependencies, so it renders offline and is easy to share with stakeholders or use when reviewing an application's attack surface.

## Basic Usage

```bash
noir scan . -f html -o report.html
```

## Preview

The screenshots below are a **real report**, generated from Noir's bundled Kemal test fixture so you can reproduce it from a checkout of the repository:

```bash
noir scan -b spec/functional_test/fixtures/crystal/kemal -f html -o report.html
```

![Noir HTML report — light theme](./report-light.png)

The report includes a built-in **dark theme**. Toggle it from the control in the top-right corner; your choice is remembered across visits (via `localStorage`) and the report also honors your operating system's `prefers-color-scheme` on first open.

![Noir HTML report — dark theme](./report-dark.png)

### What's in the report

- **Dashboard Summary**: A high-level overview of total endpoints, HTTP methods, parameters, and passive scan findings.
- **Endpoint Details**: Every discovered endpoint as a collapsible card, with a grayscale method badge (outline = safe read, gray = mutate, solid = destroy) and a protocol badge for non-HTTP endpoints such as WebSockets.
- **Parameter Breakdown**: Per-endpoint tables listing each parameter, its type (query, form, json, header, cookie, path), and value.
- **Passive Scan Results**: When passive scanning is enabled (`-P`), findings are displayed with descriptions, severity badges, and the matched code snippet.
- **Source Code Links**: The file path and line number where each endpoint was defined.

### Interactive features

The report is interactive out of the box — everything below works from the single HTML file, with no server or network access:

- **Light / dark theme toggle** that persists across visits and respects `prefers-color-scheme`.
- **Collapsible endpoint cards** so you can fold away detail and scan the surface quickly.
- **Live search** to filter endpoints by path, method, parameter, or tag, with a live "shown / total" count.
- **Method and severity filter chips** to narrow the endpoint and passive-finding lists.
- **Print-friendly**: printing forces every card open and hides the controls, and the report honors `prefers-reduced-motion`.

## Customizing the Template

Provide your own template for branding or internal reporting standards.

### Template Location

Noir looks for `report-template.html` in your configuration directory:

- **Linux/macOS**: `~/.config/noir/report-template.html`
- **Windows**: `%APPDATA%\noir\report-template.html`
- **Custom Home**: If `NOIR_HOME` is set, it looks in `$NOIR_HOME/report-template.html`.

If found, Noir uses it instead of the built-in default.

### Placeholders

Templates use placeholders that Noir replaces with generated content:

| Placeholder | Description |
| :--- | :--- |
| `<%= noir_head %>` | The contents of the `<head>` tag, including default CSS, metadata, and the pre-paint theme initializer. |
| `<%= noir_header %>` | The header section containing the title, brand mark, and theme toggle. |
| `<%= noir_summary %>` | The summary dashboard (cards showing counts). |
| `<%= noir_endpoints %>` | The main section listing all discovered endpoints, including the search box and method filter chips. |
| `<%= noir_passive_scans %>` | The section listing passive scan results. |
| `<%= noir_footer %>` | The footer section. |
| `<%= noir_scripts %>` | The interactivity scripts (theme toggle, collapsible cards, search, and filters). |

{% alert_warning() %}
Don't forget the noir_scripts placeholder — add it to your template, usually right before the closing body tag. Without it the report still renders, but the theme toggle, collapsible cards, search, and filter chips won't work.
{% end %}

### Example Template

A minimal custom template that adds a company header while reusing Noir's built-in styles, content sections, and interactivity via `<%= %>` placeholders.

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <!-- Include default styles and the pre-paint theme initializer -->
    <%= noir_head %>
    <style>
        /* Add custom overrides */
        body { background-color: #f0f2f5; }
        .company-header { padding: 20px; text-align: center; background: #333; color: #fff; }
    </style>
</head>
<body>
    <div class="company-header">
        <h1>My Company Security Report</h1>
    </div>

    <!-- Original Header -->
    <%= noir_header %>

    <main class="container">
        <!-- Summary Section -->
        <%= noir_summary %>

        <h2>Detailed Findings</h2>

        <!-- Endpoints List -->
        <%= noir_endpoints %>

        <!-- Passive Scan Results -->
        <%= noir_passive_scans %>
    </main>

    <%= noir_footer %>

    <!-- Interactivity: theme toggle, collapsible cards, search, filters -->
    <%= noir_scripts %>
</body>
</html>
```

Place this file at `~/.config/noir/report-template.html` to use it for all future reports.
