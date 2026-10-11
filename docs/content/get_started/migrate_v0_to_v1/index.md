+++
title = "Migrating from v0 to v1"
description = "What changed between Noir 0.x and 1.0: flags, config keys, behavior, and the compatibility shims that keep v0 scripts running."
weight = 5
sort_by = "weight"

+++

{% mascot(mood="question") %}
Almost every v0 invocation still runs on v1 unchanged. This page is a single place to look up the renames, behavior changes, and the few things that explicitly broke.
{% end %}

Read the short version below, then jump to the CLI, flag, or output sections that your scripts and dashboards actually touch.

## The short version

v1.0 is **compatibility-first**. v0 call shapes like `noir -b ./app -P -f json` route automatically into the `scan` subcommand, and every renamed flag keeps its old name as a silent alias. The only things that explicitly broke are `--ollama` / `--ollama-model` (deprecated since 2024; use `--ai-provider ollama [--ai-model NAME]` instead).

If you just want to upgrade and keep going, you can stop reading here. The rest of this page is for users adapting their docs, dashboards, or downstream tooling to the v1 surface.

## CLI structure

v0 used a single flat flag set. v1 introduces a verb layer so each capability has its own help page:

```
noir scan [PATHS...] [flags]   # the main endpoint discovery
noir list <techs|taggers|formats>
noir cache <info|clear|purge>
noir config <show|edit|init|path>
noir rules <list|update|path>
noir completion <zsh|bash|fish|elvish>
noir version [--verbose]
noir help [command]
```

The pre-v1 terminal flags still route to the equivalent verb:

| v0 invocation | v1 invocation |
| --- | --- |
| `noir --list-techs` | `noir list techs` |
| `noir --list-taggers` | `noir list taggers` |
| `noir --build-info` | `noir version --verbose` |
| `noir --help-all` | `noir help` |
| `noir --generate-completion zsh` | `noir completion zsh` |

`noir -v` / `noir --version` continue to print the version string.

## Deliver flag rename: PROBE / EXPORT

`noir scan -h` in v0 used a single `DELIVER` section. v1 splits it into **PROBE** (active HTTP replay against the discovered endpoints) and **EXPORT** (shipping the catalog to an external data store). The split makes it obvious that `--probe-match` / `--probe-skip` / `--probe-header` only affect probing, not the JSON/SARIF on stdout.

| v0 flag | v1 flag |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |
| `--send-es URL` | `--export-es URL` |

All v0 names still parse. They're rewritten to the v1 spelling before the option parser runs, so existing CI scripts and Dockerfiles need no changes. `noir scan -h` doesn't list the old names, so new users see only the v1 ones.

New in v1:

* `--export-opensearch URL`: speaks the same HTTP protocol as Elasticsearch.
* `--export-webhook URL`: POSTs the endpoint catalog as a single JSON document (`{endpoints, endpoint_count, noir_version}`) to any HTTP receiver (Slack incoming webhooks, Discord, Zapier/n8n, custom internal endpoints).

## Consolidated flags: `--include` and `--pvalue`

v0 had one flag per enrichment and one per parameter type. v1 folds each family into a single flag that takes a list or a `TYPE=VAL` pair. The old spellings still work as silent aliases.

| v0 flag | v1 flag |
| --- | --- |
| `--include-path` | `--include path` |
| `--include-techs` | `--include techs` |
| `--include-callee` | `--include callee` |
| `--set-pvalue VAL` | `--pvalue VAL` (or `--pvalue any=VAL`) |
| `--set-pvalue-header VAL` | `--pvalue header=VAL` |
| `--set-pvalue-cookie VAL` | `--pvalue cookie=VAL` |
| `--set-pvalue-query VAL` | `--pvalue query=VAL` |
| `--set-pvalue-form VAL` | `--pvalue form=VAL` |
| `--set-pvalue-json VAL` | `--pvalue json=VAL` |
| `--set-pvalue-path VAL` | `--pvalue path=VAL` |

Combine enrichments in one flag (`--include path,techs`) and repeat `--pvalue` for several types.

## Config file (`~/.config/noir/config.yaml`)

v0 used the same flat shape as the CLI flags, so the YAML keys followed the v0 flag names. v1 mirrors the new CLI:

| v0 config key | v1 config key |
| --- | --- |
| `send_req` | `probe` |
| `send_proxy` | `probe_via` |
| `send_es` | `export_es` |
| `send_with_headers` | `probe_header` |
| `use_matchers` | `probe_match` |
| `use_filters` | `probe_skip` |

v0 config files load unchanged: Noir renames the old keys before it merges the file into the option set. Running `noir config show` on a v0 config also prints a note that lists each v0 key and its v1 name.

If both spellings are present in the same file (mid-migration), the v1 key wins.

## Behavior changes worth noting

These don't change flag names, just what scans emit. The [v1.0.0 CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100) has the details. The highlights:

* **Default concurrency** scales with the host's CPU count (clamped to 4–32) instead of v0's fixed `"20"`. Explicit `--concurrency N` / `concurrency:` in config, or the `NOIR_CONCURRENCY` env var, still take precedence.
* **String interpolation** in route paths (Python `f""`, Ruby/Crystal/Elixir `#{}`, PHP `$var`, Kotlin `${}`) is now preserved as a `{name}` placeholder. v0 silently dropped the interpolation segment or leaked the language syntax into the URL. v1 produces a consistent template and registers the placeholder as a path parameter.
* **`Any` / `All` verbs** (Gin `r.Any`, axum `routing::any`, Echo `e.Any`, Fiber `app.All`, etc.) fan out into the concrete HTTP methods (GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD, TRACE) instead of emitting a non-HTTP `"ANY"` verb that SARIF and Postman can't ingest. `QUERY` is deliberately left out of the fan-out; it is emitted only where a route declares the verb explicitly.
* **Output to stdout** has color disabled automatically when stdout isn't a terminal, matching `ls` / `git` convention. `--no-color` and `NO_COLOR=1` still force-disable.
* **`-f json` / `-f sarif`** etc. emit a valid empty document when zero endpoints are found, instead of writing nothing. CI parsers no longer fail on an empty file.
* **`--diff-path`** disables `--probe` / `--export-*` for the comparison-side scan. Previously, an unchanged URL got probed twice (once per side) and the stale catalog got exported alongside the new one.
* **Repeat-flag accumulation** for `--exclude-path`, `--use-taggers`, `-t/--techs`, `--only-techs`, `--exclude-techs`, `--exclude-codes`, and `--ai-native-tools-allowlist`. v0 last-write-wins (the second `--exclude-techs flask` clobbered the first); v1 concatenates so each occurrence adds to the list.
* **Tagger / `--include` / `--ai-context` names** are case-insensitive (`--use-taggers Hunt` works the same as `hunt`).

## Things that explicitly broke

* `--ollama URL` / `--ollama-model NAME`: both deprecated since 2024. Use `--ai-provider ollama [--ai-model NAME]` instead. If you pass either flag, Noir stops with an error that shows the replacement command.

That's the entire breaking surface.

## Upgrading

The install paths haven't changed:

```bash
brew upgrade noir
# or
docker pull ghcr.io/owasp-noir/noir:latest
# or (latest release, Linux x86_64 binary)
gh release download -R owasp-noir/noir --pattern 'noir-v*-linux-x86_64'
```

If something stops working that this page didn't predict, please file an issue on [GitHub](https://github.com/owasp-noir/noir/issues). Silent v0 to v1 breakage is a release blocker, so we want to hear about it.
