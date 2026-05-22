+++
title = "CLI Commands"
description = "Reference for Noir's v1 subcommand surface — scan, list, cache, config, rules, completion, version, help."
weight = 1
sort_by = "weight"

+++

Starting in v1.0, Noir's CLI follows a verb-centric layout. `scan` is the
top-of-mind operation, and a small set of namespaces (`list`, `cache`,
`config`, `rules`) groups everything else.

```
noir <command> [arguments] [flags]
```

## Quick Reference

| Command                | Purpose                                                 |
|------------------------|---------------------------------------------------------|
| `noir scan PATHS...`   | Discover endpoints in one or more codebases             |
| `noir list techs`      | List supported languages, frameworks, and analyzers     |
| `noir list taggers`    | List built-in and framework-specific taggers            |
| `noir list formats`    | List supported output formats                           |
| `noir cache info`      | Show LLM cache directory, entry count, and size         |
| `noir cache clear`     | Remove every cached AI response                         |
| `noir config show`     | Print the active config file                            |
| `noir config init`     | Create the default config file (idempotent)             |
| `noir config path`     | Print the resolved config path                          |
| `noir rules list`      | List rule files installed under the rules path          |
| `noir rules update`    | Clone or pull the latest passive-scan rules             |
| `noir rules path`      | Print the configured rules directory                    |
| `noir completion zsh`  | Generate Zsh / Bash / Fish completion scripts           |
| `noir version`         | Print the version (use `--verbose` for build details)   |
| `noir help [command]`  | Show top-level help or per-command help                 |

## Scan

`noir scan` is the workhorse: it walks one or more codebases, runs
analyzers per detected technology, optionally runs the passive scanner,
and reports endpoints in the requested output format.

```bash
# Discover endpoints in a single codebase
noir scan ./app

# Scan multiple codebases in one pass
noir scan ./api ./worker ./jobs

# JSON output to a file, with passive scan enabled
noir scan ./app -P -f json -o endpoints.json

# Full AI-context enrichment plus path/techs/callees in plain output
noir scan ./app --include path,techs,callee --ai-context
```

Positional paths and repeated `-b PATH` are interchangeable — pick
whichever reads better in your scripts.

### Flag consolidation in v1

A few v0 flag families collapsed into more compact forms in v1.0. The old
forms still work as silent aliases throughout v1.x.

| v1 form                                    | v0 equivalent (still works)             |
|--------------------------------------------|-----------------------------------------|
| `--pvalue query=FOO`                       | `--set-pvalue-query FOO`                |
| `--pvalue header=X`                        | `--set-pvalue-header X`                 |
| `--pvalue FOO` (no `TYPE=`)                | `--set-pvalue FOO`                      |
| `--include path,techs,callee`              | `--include-path --include-techs --include-callee` |
| `--ai-context guards,sinks`                | `--ai-context` (no filter, all features) |
| `noir version --verbose`                   | `--build-info`                          |
| `noir completion zsh`                      | `--generate-completion zsh`             |
| `noir list techs`                          | `--list-techs`                          |
| `noir list taggers`                        | `--list-taggers`                        |
| `noir help`                                | `--help-all`                            |

### Removed in v1.0

`--ollama` and `--ollama-model` were deprecated for several releases and
are removed in v1.0. Use `--ai-provider ollama [--ai-model NAME]`
instead:

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## List

`noir list` enumerates built-in catalogs. These never grow `update`-style
verbs, so they live as static subjects under one namespace.

```bash
noir list techs       # what languages / frameworks / specs ship with Noir
noir list taggers     # built-in + framework-specific tagger plugins
noir list formats     # every supported output format
```

## Cache

`noir cache` manages the on-disk LLM response cache (`~/.config/noir/cache/ai`).

```bash
noir cache info       # location, entry count, total size
noir cache clear      # wipe every cached AI response
```

In-scan controls remain on `noir scan`: `--cache-disable` skips the cache
for one run, and `--cache-clear` wipes before scanning.

## Config

`noir config` manages the user-level YAML configuration.

```bash
noir config show      # print the active file
noir config init      # create the default config (idempotent)
noir config path      # print the resolved path
```

The config directory follows `NOIR_HOME` if set; otherwise it falls back
to `$HOME/.config/noir` on Unix and `%APPDATA%\noir` on Windows.

## Rules

`noir rules` manages the passive-scan rules repository.

```bash
noir rules list       # show installed rule files
noir rules update     # clone or pull the latest rules
noir rules path       # print the rules directory
```

The default rules path is `~/.config/noir/passive_rules` — override via
`NOIR_HOME` or with `--passive-scan-path PATH` at scan time.

## Completion

`noir completion <shell>` emits a completion script for the given shell.

```bash
noir completion zsh  > "${fpath[1]}/_noir"
noir completion bash > /etc/bash_completion.d/noir
noir completion fish > ~/.config/fish/completions/noir.fish
```

The script is subcommand-aware: typing `noir <TAB>` completes the verb
list, and `noir scan -<TAB>` completes scan flags.

## Version

`noir version` prints just the version number; `noir version --verbose`
adds Crystal, LLVM, and target-triple build details (the v0 `--build-info`
output, unchanged in content).

## Help

`noir help` shows the top-level overview, and `noir help <command>` shows
the flag surface for that command.

## v0 Compatibility

Every v0 invocation pattern continues to work in v1.x without changes:

```bash
# All three forms produce identical scan results
noir -b ./app                # v0 (router default-route to scan)
noir scan ./app              # v1 idiomatic
noir scan -b ./app           # v1 explicit + v0-shaped flags
```

The router falls back to `scan` whenever `ARGV[0]` is not a known verb,
so CI pipelines, GitHub Actions, Dockerfile entrypoints, and shell
aliases all roll forward to v1.0 without edits.

Deprecation warnings will land in a later v1.x release; verb-form
becomes mandatory only at v2.x.
