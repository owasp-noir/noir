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

Settings in the config file are defaults; command-line flags override them. Use `--config-file <path>` to load a config from a non-default location:

```bash
noir scan . --config-file ./ci/noir.yaml
```

You can also manage the config file directly through `noir config`:

```bash
noir config init   # create the default config (idempotent)
noir config show   # print the active file
noir config edit   # open the file in $VISUAL / $EDITOR
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

# Base URL for probing; also required by exclude_codes / status_codes / probe
url: "https://api.example.com"

# Exclude certain status codes (needs a target URL, so it pairs with `url` above)
exclude_codes: "404,500"

# Enable all taggers by default
all_taggers: true

# Attach 1-hop handler callees to each endpoint
include_callee: true

# Attach AI review context (guards, callee, sources, sinks, validators, signals)
ai_context: true

# Default AI provider and model
ai_provider: "openai"
ai_model: "gpt-5.5"

# Passive security scan (equivalent to -P / --passive-scan)
passive_scan: false
passive_scan_severity: "high"

# Exit with code 2 if any analyzer failed or skipped a file
strict: false

# Disable loading spinner animations
no_spinner: false

# Fire HTTP probes at discovered endpoints (needs `url`)
probe: false

# Skip TLS certificate verification for probe/export (insecure)
tls_skip_verify: false
```

This is equivalent to running:

```bash
noir scan /path/to/my/project -f json -u https://api.example.com --exclude-codes "404,500" -T \
  --include callee --ai-context \
  --ai-provider openai --ai-model gpt-5.5
```

## Key reference

`noir config init` writes a fully commented file with every supported key. The example above is a curated subset; CLI flags always override the file. Keys below match the generated file (legacy v0 names such as `send_es` / `send_proxy` still load, but migrate to the v1 names).

### Scan paths and scope

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `base` | string or list | positional paths / `-b` | Default path(s) to scan |
| `url` | string | `-u` / `--url` | Base URL for paths; required by status/probe options |
| `exclude_path` | CSV globs | `--exclude-path` | Skip matching files |
| `techs` | CSV | `-t` / `--techs` | Add techs to the analyzer set (on top of auto-detect) |
| `only_techs` | CSV | `--only-techs` | Restrict which tech detectors run |
| `exclude_techs` | CSV | `--exclude-techs` | Drop techs from the final set after detection |
| `concurrency` | int | `--concurrency` | Worker count |

### Output

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `format` | string | `-f` / `--format` | `plain`, `json`, `yaml`, `oas3`, `curl`, … |
| `output` | string | `-o` / `--output` | Write results to this file |
| `color` | bool | inverse of `--no-color` | ANSI color in plain output |
| `nolog` | bool | `--no-log` | Show results only |
| `no_spinner` | bool | `--no-spinner` | Disable spinner animations |
| `strict` | bool | `--strict` | Exit `2` when an analyzer fails or skips a file |
| `status_codes` | bool | `--status-codes` | Probe and attach HTTP status codes (needs `url`) |
| `exclude_codes` | CSV | `--exclude-codes` | Drop probed statuses (pairs with `status_codes`) |
| `include_path` | bool | `--include path` | Legacy boolean form of `--include` |
| `include_techs` | bool | `--include techs` | Legacy boolean form of `--include` |
| `include_callee` | bool | `--include callee` | Attach 1-hop handler callees |
| `ai_context` | bool | `--ai-context` | Attach AI review context |
| `ai_context_features` | CSV | `--ai-context LIST` | Subset: `guards`, `callee`, `sources`, `sinks`, `validators`, `signals` |

### Parameter values

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `set_pvalue` | list | `--pvalue any=…` | Fill values for every param type |
| `set_pvalue_header` | list | `--pvalue header=…` | Header values |
| `set_pvalue_cookie` | list | `--pvalue cookie=…` | Cookie values |
| `set_pvalue_query` | list | `--pvalue query=…` | Query values |
| `set_pvalue_form` | list | `--pvalue form=…` | Form values |
| `set_pvalue_json` | list | `--pvalue json=…` | JSON body values |
| `set_pvalue_path` | list | `--pvalue path=…` | Path values |

### Passive scan and taggers

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `passive_scan` | bool | `-P` / `--passive-scan` | Enable passive scan |
| `passive_scan_path` | list | `--passive-scan-path` | Custom rule directories (replaces bundled rules) |
| `passive_scan_severity` | string | `--passive-scan-severity` | `critical` / `high` / `medium` / `low` |
| `passive_scan_auto_update` | bool | `--passive-scan-auto-update` | Update rules at startup |
| `passive_scan_no_update_check` | bool | `--passive-scan-no-update-check` | Skip update check |
| `all_taggers` | bool | `-T` / `--use-all-taggers` | Enable every tagger |
| `use_taggers` | CSV | `--use-taggers` | Enable selected taggers |

### Probe and export

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `probe` | bool | `--probe` | Send HTTP requests to discovered endpoints (needs `url`) |
| `probe_via` | string | `--probe-via` | Proxy URL for probes |
| `probe_header` | list | `--probe-header` | Extra probe headers |
| `probe_match` | list | `--probe-match` | Only probe matching endpoints |
| `probe_skip` | list | `--probe-skip` | Skip matching endpoints |
| `tls_skip_verify` | bool | `--tls-skip-verify` | Skip TLS verify for probe/export/webhook |
| `export_es` | string | `--export-es` / `--export-opensearch` | Elasticsearch or OpenSearch URL (both flags write this key) |
| `export_webhook` | string | `--export-webhook` | POST catalog JSON to this URL |

### AI and cache

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `ai_provider` | string | `--ai-provider` | Provider prefix or full URL |
| `ai_model` | string | `--ai-model` | Model name |
| `ai_key` | string | `--ai-key` / `NOIR_AI_KEY` | Prefer the env var in shared configs |
| `ai_agent` | bool | `--ai-agent` | Enable the agentic tool-calling loop |
| `ai_agent_max_steps` | int | `--ai-agent-max-steps` | Agent loop cap |
| `ai_native_tools_allowlist` | CSV | `--ai-native-tools-allowlist` | Providers allowed to use native tools |
| `ai_max_token` | int | `--ai-max-token` | Max tokens per request (`0` = provider default) |
| `cache_disable` | bool | `--cache-disable` | Disable the LLM response cache |
| `cache_clear` | bool | `--cache-clear` | Clear the cache before the run |

### Diff and diagnostics

| Key | Type | CLI equivalent | Notes |
|---|---|---|---|
| `diff` | string | `--diff-path` | Prior code path for diff output |
| `config_file` | string | `--config-file` | Usually set only via CLI |
| `debug` | bool | `-d` / `--debug` | Debug logging |
| `verbose` | bool | `--verbose` | Verbose logging (`--include path` + all taggers) |


