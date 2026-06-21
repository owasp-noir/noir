+++
title = "Managing Technology Scopes"
description = "Control which technologies Noir scans using the techs and exclude-techs flags."
weight = 3
sort_by = "weight"

+++

Noir can include or exclude specific technologies during scanning, letting you focus on relevant frameworks and reduce noise.

## Flags

*   `--techs <TECHS>`: Add these techs to the analyzer set in addition to auto-detected ones (comma-separated, e.g., `rails,django`).
*   `--only-techs <TECHS>`: Restrict auto-detection to these tech detectors (comma-separated, e.g., `rails,django`).
*   `--exclude-techs <TECHS>`: Exclude the specified technologies from the scan.
*   `noir list techs`: List all technologies Noir supports.

### Include specific technologies

```bash
noir scan . --techs rails
```

### Restrict auto-detection to specific technologies

```bash
noir scan . --only-techs rails
```

### Exclude specific technologies

```bash
noir scan . --exclude-techs express,koa
```

### List available technologies

```bash
noir list techs
```
