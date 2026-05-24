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

Settings in config file are defaults and can be overridden via command line. Use `--config-file <path>` to load a config from a non-default location:

```bash
noir scan . --config-file ./ci/noir.yaml
```

You can also manage the config file directly through `noir config`:

```bash
noir config init   # create the default config (idempotent)
noir config show   # print the active file
noir config path   # print the resolved path
```

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

# Attach 1-hop handler callees to each endpoint
include_callee: true

# Attach AI review context (guards, sinks, validators, signals)
ai_context: true

# Default AI provider and model
ai_provider: "openai"
ai_model: "gpt-5.5"
```

This is equivalent to running:

```bash
noir scan /path/to/my/project -f json --exclude-codes "404,500" -T \
  --include callee --ai-context \
  --ai-provider openai --ai-model gpt-5.5
```

