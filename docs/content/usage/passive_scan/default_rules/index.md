+++
title = "Default Passive Scan Rules"
description = "Default passive scan rules location, auto-update behavior, and customization."
weight = 2
sort_by = "weight"

+++

Noir includes curated default rules for detecting common security vulnerabilities. When passive scanning is enabled (`-P`), Noir automatically initializes rules on first run, checks for updates, and optionally auto-updates them.

## Rule Locations

| OS      | Path                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

## Automatic Initialization and Update Checks

With `-P` enabled, Noir:
1. Initializes rules on first run by cloning [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) to `~/.config/noir/passive_rules/`
2. Checks for updates by comparing local and remote repositories
3. Notifies you when rules are outdated
4. Optionally auto-updates when enabled

Repository: https://github.com/owasp-noir/noir-passive-rules

## CLI Options

- `--passive-scan-auto-update` — Auto-update rules on startup
- `--passive-scan-no-update-check` — Skip update checks (useful for air-gapped environments)

Both options are also configurable via `~/.config/noir/config.yaml`.

## Example Usage

```bash
# Default behavior - check for updates and notify if behind
noir -b /app -P

# Auto-update rules on startup
noir -b /app -P --passive-scan-auto-update

# Skip update checks completely
noir -b /app -P --passive-scan-no-update-check
```

## Sample Output

First run (auto-initialization):
```
⚬ Passive scanner enabled.
⚬ Initializing passive rules directory...
✔ Passive rules initialized successfully.
  ├── Using default passive rules.
  └── Loaded 15 valid passive scan rules.
```

When updates are available:
```
⚬ Passive scanner enabled.
❏ Checking for passive rules updates...
▲ Passive rules are 3 commits behind the latest version.
  ├── Run 'git pull' in ~/.config/noir/passive_rules/ to update
  ├── Or use 'git clone https://github.com/owasp-noir/noir-passive-rules.git ~/.config/noir/passive_rules/' to get the latest rules
  ├── Or run 'noir -b . -P --passive-scan-auto-update' to auto-update on startup
```

With auto-update enabled:
```
⚬ Passive scanner enabled.
❏ Checking for passive rules updates...
⚬ Updating passive rules (3 commits behind)...
✔ Passive rules updated successfully.
```

## Customizing Rules

Add custom `.yml` or `.yaml` rule files to the same directory. They are automatically loaded on the next passive scan without modifying the default rule set.
