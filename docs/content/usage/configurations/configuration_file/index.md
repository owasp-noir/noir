+++
title = "Using a Configuration File"
description = "Learn how to use a `config.yaml` file to set default options for Noir. This is a great way to streamline your workflow and ensure consistent scans."
weight = 1
sort_by = "weight"

[extra]
+++

To make running Noir easier and more consistent, you can use a configuration file to set default values for many of the command-line flags. This saves you from having to type the same options every time you run a scan.

## Configuration File Location

Noir looks for a file named `config.yaml` in a specific directory depending on your operating system:

| OS | Path |
|---|---|
| macOS | `~/.config/noir/` |
| Linux | `~/.config/noir/` |
| Windows | `%APPDATA%\noir\` |

Any settings you define in this file will be used as the default, but you can always override them by providing a different value on the command line.

## Noir Home Directory Structure

Noir stores configuration and cache under the same home directory (see the paths above). A typical structure looks like:

```
~/.config/noir/
├── config.yaml          # Main configuration file
├── cache/
│   └── ai/              # LLM response cache (used by AI-powered analysis)
└── passive_rules/       # Rules directory for Passive Scan
```

- config.yaml: Your main configuration file.
- cache/ai: Stores AI response cache to speed up repeated analyses and reduce costs.
- passive_rules: Contains rule files for Passive Scan.

## Example `config.yaml`

Here is an example of a `config.yaml` file with some common settings:

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

With this configuration, you could simply run `noir` and it would be equivalent to running:

```bash
noir -b /path/to/my/project -f json --exclude-codes "404,500" -T --ai-provider openai --ai-model gpt-4o
```

By using a configuration file, you can create a personalized and efficient workflow that is tailored to your specific needs.

