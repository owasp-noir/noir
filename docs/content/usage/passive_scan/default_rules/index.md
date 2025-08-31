+++
title = "Default Passive Scan Rules"
description = "Learn where Noir stores its default passive scanning rules and how you can extend them with your own custom rules to enhance your security analysis."
weight = 2
sort_by = "weight"

[extra]
+++

Noir comes with a set of default rules for its passive scanning feature. These rules are curated by the Noir team to detect common security vulnerabilities. When passive scanning is enabled (`-P`), Noir will automatically initialize the rules on first run, check for updates on startup, notify you if your local rules are behind, and can optionally auto-update them.

## Rule Locations

The default rules are stored in a specific directory depending on your operating system:

| OS      | Path                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

When you run a passive scan with the `-P` or `--passive-scan` flag, Noir looks for rules in this directory.

## Automatic Initialization and Update Checks

When passive scanning is enabled (`-P`), Noir now:
1. Initializes rules on first run by cloning the [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) repository to `~/.config/noir/passive_rules/`
2. Checks for updates by comparing the local Git repository with the remote on startup
3. Notifies you when rules are outdated, including clear instructions to update
4. Optionally auto-updates the rules when enabled

Repository: https://github.com/owasp-noir/noir-passive-rules

## New CLI Options

- `--passive-scan-auto-update` — Automatically update rules from the repository at startup
- `--passive-scan-no-update-check` — Skip update checking entirely (useful for air-gapped environments)

These options are also configurable via `~/.config/noir/config.yaml`.

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

## Customizing the Rules

While the default rules are a great starting point, you may want to add your own rules to look for issues that are specific to your organization or application. To do this, you can simply create a new YAML rule file and place it in the same directory as the default rules.

Any `.yml` or `.yaml` file you add to this directory will be automatically loaded and used by the passive scanner the next time you run it. This allows you to easily extend and customize Noir's passive scanning capabilities to meet your specific needs without having to modify the default rule set.
