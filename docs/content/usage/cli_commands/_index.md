+++
title = "CLI Commands"
description = "Subcommands available in Noir v1: scan, list, cache, config, rules, completion, version, help."
weight = 1
sort_by = "weight"

+++

Starting with v1.0, Noir's CLI uses a verb-based layout. `scan` is the
main command. A few namespaces (`list`, `cache`, `config`, `rules`)
group the rest.

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
| `noir config edit`     | Open the config file in `$VISUAL` / `$EDITOR`           |
| `noir config init`     | Create the default config file (idempotent)             |
| `noir config path`     | Print the resolved config path                          |
| `noir rules list`      | List rule files installed under the rules path          |
| `noir rules update`    | Clone or pull the latest passive-scan rules             |
| `noir rules path`      | Print the configured rules directory                    |
| `noir completion zsh`  | Generate Zsh / Bash / Fish / Elvish completion scripts  |
| `noir version`         | Print the version (use `--verbose` for build details)   |
| `noir help [command]`  | Show top-level help or per-command help                 |

## Scan

`noir scan` walks one or more codebases, runs analyzers for each
detected technology, optionally runs the passive scanner, and reports
endpoints in the requested format.

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

Positional paths and repeated `-b PATH` work the same way. Use whichever
reads better in your scripts.

> Multiple codebases — whether positional (`noir scan ./api ./worker`) or
> repeated `-b` — are scoped as sibling roots, the supported monorepo
> shape. Nested or overlapping roots (e.g. `noir scan /repo /repo/sub`)
> don't compose cross-base prefixes, since a definition and its use can
> resolve to different longest-matching roots; prefer sibling layouts.

### Flag consolidation in v1

A few v0 flag families collapsed into shorter forms in v1.0. The old
forms still work as silent aliases throughout v1.x.

| v1 form                                    | v0 equivalent (still works)             |
|--------------------------------------------|-----------------------------------------|
| `--probe`                                  | `--send-req`                            |
| `--probe-via URL`                          | `--send-proxy URL`                      |
| `--probe-header VAL`                       | `--with-headers VAL`                    |
| `--probe-match VAL`                        | `--use-matchers VAL`                    |
| `--probe-skip VAL`                         | `--use-filters VAL`                     |
| `--export-es URL`                          | `--send-es URL`                         |
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

The deliver family was split into two semantic sections in `noir scan -h`: **PROBE** for active HTTP replay against the discovered endpoints and **EXPORT** for shipping the endpoint catalog to an external data store (Elasticsearch, OpenSearch, webhook). See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md) for the full surface, and [Migrating from v0 to v1](@/get_started/migrate_v0_to_v1/index.md) for the rationale and the new exports added in v1.

### Removed in v1.0

`--ollama` and `--ollama-model` were deprecated for several releases and
are removed in v1.0. Use `--ai-provider ollama [--ai-model NAME]`
instead:

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## List

`noir list` shows built-in catalogs. These never grow `update`-style
actions, so they live as static subjects under one namespace.

```bash
noir list techs       # supported languages, frameworks, and specs
noir list taggers     # built-in and framework-specific tagger plugins
noir list formats     # every supported output format
```

## Cache

`noir cache` manages the on-disk LLM response cache at
`~/.config/noir/cache/ai`.

```bash
noir cache info       # location, entry count, total size
noir cache clear      # remove every cached AI response
```

In-scan controls stay on `noir scan`: `--cache-disable` skips the cache
for one run, and `--cache-clear` clears it before scanning.

## Config

`noir config` manages the user-level YAML configuration.

```bash
noir config show      # print the active file
noir config edit      # open the file in $VISUAL / $EDITOR
noir config init      # create the default config (idempotent)
noir config path      # print the resolved path
```

The config directory follows `NOIR_HOME` if set. Otherwise it falls back
to `$HOME/.config/noir` on Unix and `%APPDATA%\noir` on Windows.

`noir config edit` resolves the editor in the order `$VISUAL`,
`$EDITOR`, then a platform default (`vi` on Unix, `notepad` on Windows).
The config file is created first if it does not exist yet.

## Rules

`noir rules` manages the passive-scan rules repository.

```bash
noir rules list       # show installed rule files
noir rules update     # clone or pull the latest rules
noir rules path       # print the rules directory
```

The default rules path is `~/.config/noir/passive_rules`. Override it
via `NOIR_HOME`, or with `--passive-scan-path PATH` at scan time.

## Completion

`noir completion <shell>` emits a completion script for the given shell.

```bash
noir completion zsh    > "${fpath[1]}/_noir"
noir completion bash   > /etc/bash_completion.d/noir
noir completion fish   > ~/.config/fish/completions/noir.fish
noir completion elvish > ~/.config/elvish/lib/noir.elv  # then `use noir` from rc.elv
```

The script knows about every subcommand. Typing `noir <TAB>` completes
the verb list. `noir scan -<TAB>` completes scan flags. The Elvish
variant registers the same completer at
`$edit:completion:arg-completer[noir]`.

## Version

`noir version` prints the version number. `noir version --verbose` adds
Crystal, LLVM, and target-triple build details (the same content the v0
`--build-info` flag produced).

## Help

`noir help` shows the top-level overview. `noir help <command>` shows
the flags for a specific command.

## Global flags

A small set of flags work on every subcommand, not just `scan`:

| Flag           | Effect                                                                |
|----------------|----------------------------------------------------------------------|
| `--no-color`   | Strip ANSI color from every command's output (also honors `NO_COLOR`) |
| `-v, --version`| Print the noir version and exit                                       |
| `-h, --help`   | Show help for the current command                                     |

Per-command flags (output format, concurrency, passive scan, AI
provider, and so on) live under `noir scan`. See `noir help scan` for
the full list.

## v0 Compatibility

Every v0 invocation pattern keeps working in v1.x without changes:

```bash
# All three forms produce identical scan results
noir -b ./app                # v0 form (routed to scan)
noir scan ./app              # v1 form
noir scan -b ./app           # v1 verb with v0-style flags
```

When `ARGV[0]` is not a known verb, the router falls back to `scan`.
CI pipelines, GitHub Actions, Dockerfile entrypoints, and shell aliases
all keep working without edits.

Deprecation warnings will land in a later v1.x release. The verb form
becomes mandatory only at v2.x.
