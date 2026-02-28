+++
title = "Managing Technology Scopes"
description = "Control which technologies Noir scans using the techs and exclude-techs flags."
weight = 3
sort_by = "weight"

+++

Noir can include or exclude specific technologies during scanning, letting you focus on relevant frameworks and reduce noise.

## Flags

*   `--techs <TECHS>`: Only scan the specified technologies (comma-separated, e.g., `rails,django`).
*   `--exclude-techs <TECHS>`: Exclude the specified technologies from the scan.
*   `--list-techs`: List all technologies Noir supports.

### Include specific technologies

```bash
noir -b . --techs rails
```

### Exclude specific technologies

```bash
noir -b . --exclude-techs express,koa
```

### List available technologies

```bash
noir --list-techs
```
