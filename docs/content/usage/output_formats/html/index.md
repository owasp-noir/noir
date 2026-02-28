+++
title = "HTML Report"
description = "Generate a comprehensive, visual HTML report of your attack surface scan results."
weight = 3
sort_by = "weight"

+++

Generate a self-contained, interactive HTML file that visualizes scan results. Suitable for sharing with stakeholders or reviewing the application's attack surface.

## Basic Usage

```bash
noir -b . -f html -o report.html
```

### Features

- **Dashboard Summary**: A high-level overview of total endpoints, parameters, and passive scan findings.
- **Endpoint Details**: A list of all discovered endpoints, categorized by HTTP method.
- **Parameter Breakdown**: Detailed tables showing parameters, their types (query, form, json, etc.), and values.
- **Passive Scan Results**: If passive scanning is enabled, findings are displayed with descriptions, severity levels, and code snippets.
- **Source Code Links**: File paths and line numbers pointing to where the endpoints were defined.

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
| `<%= noir_head %>` | The contents of the `<head>` tag, including default CSS and metadata. |
| `<%= noir_header %>` | The header section containing the title and logo. |
| `<%= noir_summary %>` | The summary dashboard (cards showing counts). |
| `<%= noir_endpoints %>` | The main section listing all discovered endpoints. |
| `<%= noir_passive_scans %>` | The section listing passive scan results. |
| `<%= noir_footer %>` | The footer section. |

### Example Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <!-- Include default styles and scripts -->
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
</body>
</html>
```

Place this file at `~/.config/noir/report-template.html` to use it for all future reports.
