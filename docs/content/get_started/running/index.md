+++
title = "Your First Scan"
description = "Run your first scan with Noir and explore the results."
weight = 3
sort_by = "weight"

+++

Now that Noir is installed, let's scan a real project. You'll point Noir at a codebase, see what it finds, and learn how to shape the output.

## Run a Scan

Pick a project directory and scan it:

```bash
noir -b /path/to/your/app
```

Or if you're already inside the project:

```bash
noir -b .
```

![](./running.png)

Noir reads the source files, detects which frameworks are in use, and prints every endpoint it finds — methods, paths, parameters, headers, and cookies.

## Check What Was Detected

Curious which technologies Noir picked up? Add `--include-techs` to see them alongside the results:

```bash
noir -b . --include-techs
```

To see every technology Noir knows how to analyze:

```bash
noir --list-techs
```

If your framework isn't listed, you can still use [AI-powered analysis](@/get_started/ai_power/index.md) to detect endpoints.

## Try Different Output Formats

The default output is a human-readable table. Depending on your workflow, you might want something else:

```bash
# Machine-readable JSON for scripting and pipelines
noir -b . -f json

# YAML for easy reading and config-friendly workflows
noir -b . -f yaml

# OpenAPI spec — useful for generating API docs or feeding into tools
noir -b . -f oas3

# cURL commands you can run immediately against a live target
noir -b . -f curl -u https://your-target.com
```

See all available formats in the [Output Formats](@/usage/output_formats/_index.md) section.

## Save Results to a File

Instead of printing to the terminal, write the output to a file with `-o`:

```bash
noir -b . -f json -o results.json
```

This is useful for diffing results between scans, feeding into CI pipelines, or sharing with your team.

## Trace Endpoints Back to Source

Want to know exactly where an endpoint was defined? Add `--include-path` to show source file locations:

```bash
noir -b . --include-path
```

Combine it with other options for a complete picture:

```bash
noir -b . --include-path --include-techs -f json -o results.json
```

## Focus Your Scan

Large monorepos may contain many frameworks. You can narrow the scan to what matters:

```bash
# Only scan for Rails and Django endpoints
noir -b . --techs rails,django

# Scan everything except Express
noir -b . --exclude-techs express
```

## Quick Reference

| Flag | What it does |
|---|---|
| `-b <path>` | Directory to scan |
| `-f <format>` | Output format (json, yaml, oas3, curl, etc.) |
| `-o <file>` | Write output to a file |
| `-u <url>` | Base URL for cURL/HTTPie output |
| `--include-path` | Show source file locations |
| `--include-techs` | Show detected technologies |
| `--techs` | Only scan these frameworks |
| `--exclude-techs` | Skip these frameworks |
| `--verbose` | Detailed logging |
| `--no-log` | Suppress all logs |
| `--help` | Full help |

---

You've completed the Getting Started guide! Here's what to explore next:

- **[Configurations](@/usage/configurations/configuration_file/index.md)** — Set default options so you don't repeat flags every time
- **[Output Formats](@/usage/output_formats/_index.md)** — Dive deeper into all output formats
- **[Passive Scan](@/usage/passive_scan/_index.md)** — Scan for security issues like hardcoded secrets and misconfigurations
- **[AI Power](@/get_started/ai_power/index.md)** — Use AI to detect endpoints in unsupported frameworks
