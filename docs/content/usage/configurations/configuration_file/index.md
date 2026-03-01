+++
title = "Using a Configuration File"
description = "Set default options for Noir using a config.yaml file."
weight = 1
sort_by = "weight"

+++

Use a `config.yaml` file to set default options for consistent scans.

## File Location

| OS | Path |
|---|---|
| macOS | `~/.config/noir/` |
| Linux | `~/.config/noir/` |
| Windows | `%APPDATA%\noir\` |

Settings in config file are defaults and can be overridden via command line.

## Directory Structure

```
~/.config/noir/
├── config.yaml          # Configuration file
├── cache/
│   └── ai/              # LLM response cache
└── passive_rules/       # Passive scan rules
```

## Example `config.yaml`

```yaml
---
# Default base path for scans
base: "/path/to/my/project"

# Always use color in the output
color: true

# Default output format
format: "json"

# Exclude certain status codes
exclude_codes: "404,500"

# Enable all taggers by default
all_taggers: true

# Default AI provider and model
ai_provider: "openai"
ai_model: "gpt-4o"
```

This is equivalent to running:

```bash
noir -b /path/to/my/project -f json --exclude-codes "404,500" -T --ai-provider openai --ai-model gpt-4o
```

