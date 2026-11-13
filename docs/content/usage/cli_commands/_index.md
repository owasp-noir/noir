+++
title = "CLI Commands"
description = "Subcommands available in Noir v1: scan, trace, reach, query, list, cache, config, rules, completion, version, help."
weight = 1
sort_by = "weight"

+++

Starting with v1.0, Noir's CLI uses a verb-based layout. `scan` is the
main command, alongside query verbs (`trace`, `reach`, `query`)
and namespaces (`list`, `cache`, `config`, `rules`).

```
noir <command> [arguments] [flags]
```

## Quick Reference

**Scan**

| Command                | Purpose                                                 |
|------------------------|---------------------------------------------------------|
| `noir scan PATHS...`   | Discover endpoints in one or more codebases             |

**Query**

| Command                | Purpose                                                 |
|------------------------|---------------------------------------------------------|
| `noir trace "<METHOD> <URL>"` | Map a request to its route, guards, params and sinks |
| `noir reach FILE[:LINE]` | List the endpoints that touch a source file           |
| `noir query [FILTERS]` | Search the attack surface with AND-ed filters           |

**Management**

| Command                | Purpose                                                 |
|------------------------|---------------------------------------------------------|
| `noir list techs`      | List supported languages, frameworks, and analyzers     |
| `noir list taggers`    | List built-in and framework-specific taggers            |
| `noir list formats`    | List supported output formats                           |
| `noir cache info`      | Show LLM cache directory, entry count, and size         |
| `noir cache clear`     | Remove every cached AI response                         |
| `noir cache purge <days>` | Remove cached entries older than N days              |
| `noir config show`     | Print the active config file                            |
| `noir config edit`     | Open the config file in `$VISUAL` / `$EDITOR`           |
| `noir config init`     | Create the default config file (idempotent)             |
| `noir config path`     | Print the resolved config path                          |
| `noir rules list`      | List rule files installed under the rules path          |
| `noir rules update`    | Clone or pull the latest passive-scan rules             |
| `noir rules path`      | Print the configured rules directory                    |

**Utility**

| Command                | Purpose                                                 |
|------------------------|---------------------------------------------------------|
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

> Pass multiple codebases as sibling roots (`noir scan ./api ./worker`,
> or repeated `-b`). That is the supported monorepo shape. Nested or
> overlapping roots (e.g. `noir scan /repo /repo/sub`) don't combine route
> prefixes across bases, because a definition and its use can resolve to
> different roots.

### Scan flags

`noir scan -h` groups its flags into these sections. Each section has its
own page with the details.

| Section | Flags | Details |
|---------|-------|---------|
| BASE | `-b/--base-path`, `-u/--url` | [Your First Scan](@/get_started/running/index.md) |
| OUTPUT | `-f/--format`, `-o/--output`, `--pvalue`, `--status-codes`, `--exclude-codes`, `--exclude-path`, `--include`, `--ai-context`, `--no-color`, `--no-spinner`, `--no-log`, `--strict` | [Output Formats](@/usage/output_formats/_index.md), [AI Context Coverage](@/usage/supported/ai_context_coverage/index.md) |
| PASSIVE SCAN | `-P/--passive-scan`, `--passive-scan-path`, `--passive-scan-severity`, `--passive-scan-auto-update`, `--passive-scan-no-update-check` | [Passive Scanning](@/usage/passive_scan/_index.md) |
| TAGGER | `-T/--use-all-taggers`, `--use-taggers`, `--tagger-rules` | [Tagger](@/usage/more_features/tagger/index.md) |
| PROBE | `--probe`, `--probe-via`, `--probe-header`, `--probe-match`, `--probe-skip`, `--tls-skip-verify` | [Deliver](@/usage/more_features/deliver/index.md) |
| EXPORT | `--export-es`, `--export-opensearch`, `--export-webhook` | [Deliver](@/usage/more_features/deliver/index.md) |
| AI Integration | `--ai-provider`, `--ai-model`, `--ai-key`, `--ai-key-file`, `--ai-temperature`, `--ai-seed`, `--ai-agent`, `--ai-agent-max-steps`, `--ai-dry-run`, `--ai-include-sensitive`, `--ai-no-optimize`, `--ai-native-tools-allowlist`, `--ai-scope`, `--ai-max-token`, `--ai-stream`, `--ai-max-requests` | [AI Providers](@/usage/ai_providers/_index.md), [AI Power](@/get_started/ai_power/index.md) |
| DIFF | `--diff-path`, `--diff-ref`, `--fail-on` | [Diff](@/usage/more_features/diff/index.md) |
| TECHNOLOGIES | `-t/--techs`, `--only-techs`, `--exclude-techs` | [Managing Technology Scopes](@/usage/supported/tech-commands/index.md) |
| CONFIG | `--config-file`, `--concurrency` | [Configuration File](@/usage/configurations/configuration_file/index.md) |
| CACHE | `--cache-disable`, `--cache-clear` | [Cache](#cache) below |
| DEBUG | `-d/--debug`, `--verbose`, `-h/--help` | `--verbose` also turns on `--include path` and `--use-all-taggers` |

A scan exits with `0` on success. `--strict` makes it exit with `2` when
an analyzer failed or skipped a file, and `--fail-on` makes a diff scan
exit with `3` when the diff has one of the listed change types. Both
still write the full report first.

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
| `--pvalue cookie=X`                        | `--set-pvalue-cookie X`                 |
| `--pvalue form=X`                          | `--set-pvalue-form X`                   |
| `--pvalue json=X`                          | `--set-pvalue-json X`                   |
| `--pvalue path=X`                          | `--set-pvalue-path X`                   |
| `--pvalue FOO` (no `TYPE=`)                | `--set-pvalue FOO`                      |
| `--include path,techs,callee`              | `--include-path --include-techs --include-callee` |
| `--ai-context guards,sinks`                | `--ai-context` (no filter, all features) |
| `noir version --verbose`                   | `--build-info`                          |
| `noir completion zsh`                      | `--generate-completion zsh`             |
| `noir list techs`                          | `--list-techs`                          |
| `noir list taggers`                        | `--list-taggers`                        |
| `noir help`                                | `--help-all`                            |

The v0 deliver flags are now split into two sections of `noir scan -h`: **PROBE** sends HTTP requests to the discovered endpoints, and **EXPORT** sends the endpoint list to an external store (Elasticsearch, OpenSearch, webhook). See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md) for every flag, and [Migrating from v0 to v1](@/get_started/migrate_v0_to_v1/index.md) for why it changed and which exports are new in v1.

### Removed in v1.0

`--ollama` and `--ollama-model` were deprecated for several releases and
are removed in v1.0. Use `--ai-provider ollama [--ai-model NAME]`
instead:

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## Trace, Reach, Query

Three query verbs for tracking endpoints rather than listing them. They are
the shape an AI agent (or a reviewer with a specific question) needs: ask a
narrow question, get a small answer. Each runs a scan with
`--ai-context all --include callee` implied and accepts every `scan` flag, or
reads a saved report with `--from` so one scan answers many questions.

```bash
noir scan ./app -f json --ai-context --include callee -o report.json   # once

noir trace "POST /api/users/42" --from report.json     # request → route, guards, params, sinks, callees
noir reach src/handlers/users.go:57 --from report.json # file → endpoints declared in or calling into it
noir query --no-guard --sink any --from report.json    # unauthenticated routes that reach any sink
```

### Trace

```bash
noir trace "<METHOD> <URL>" [paths...] [flags]
noir trace <URL> [paths...] [flags]              # every method at that path
```

`trace` maps a concrete request path onto the declared route: `/api/users/42`
matches `/api/users/{id}`, `:id`, `<int:pk>`, `[id]` and `*`, and a HEAD
request traces to the GET route. When no method is given, it lists matching
routes for any method at that path. Live scan paths can be passed directly,
such as `noir trace "POST /api/users/42" ./app`.

Every matching route is printed, most specific first, with `matched_by`
(`exact`, `pattern`, `wildcard`, or `prefix` for a proxy prefix location or
a Go ServeMux `/x/` subtree). In `jsonl` (default) and `json`, `trace` prints
the full endpoint record under `endpoint`. In `text` format (`-f text`), it
prints a compact one-line summary.

On a miss, it prints the nearest routes as `candidates` (scored by shared
leading segments, edit distance on the first differing segment, and difference
in path length) and
exits with code 1. In `jsonl` and `json`, a miss emits
`{"query": "<label>", "match": false, "candidates": [...]}`; in `text`, it
prints `no match: <label>` followed by each candidate. When only a wildcard
or prefix route matched (such as `/*unmatched_route`), candidate routes are
also printed after the match in case the request path was a typo.

### Reach

```bash
noir reach <FILE[:LINE]> [paths...] [flags]
```

`reach` matches `FILE` as a path suffix against every location Noir recorded:
route declarations, the handler definition, callees, guards, sources, sinks,
and validators. It lists the evidence in `via` (`kind:name@line` or
`kind@line`), and an entry outside the row's own file carries its path (`@path:line`).
When `:LINE` is given, evidence and rows are ordered by distance to that line
and `nearest_line` is set. Noir records declaration lines, not function
spans, so the line orders rather than filters. Inheritance and dynamic loading
are not followed.

If no recorded location matches `FILE`, `reach` prints a hint on
stderr and exits with code 1. If `:LINE` is given but no line was recorded for
the evidence in that file, a notice is printed on stderr.

### Query

```bash
noir query [filters] [paths...] [flags]
```

`query` filters AND together.

Filters that accept a comma-separated list match with OR:
- `--method GET,POST`: HTTP method (`--method POST` also matches routes declared as `ANY`, while `--method ANY` matches only `ANY` routes)
- `--project <dir,...>`: project directory of a monorepo relative to the scan base (exact, or glob when containing `*`, `?`, `[`)
- `--tech <name,...>`: technology name (e.g. `go_gin`, `python_django`)
- `--tag <name,...>`: tag name (`auth`, `admin`, ...)
- `--param <name,...>`: parameter name (case-insensitive for header parameters)
- `--param-type <type,...>`: parameter type (`query`, `json`, `form`, `header`, `cookie`, `path`)
- `--protocol <proto,...>`: protocol (`http`, `ws`, `cli`, ...)
- `--sink <kind,...|any>`: reaches a sink of this kind (`sql`, `command_exec`, `file_io`, `outbound_http`, `template_render`, `redirect`, `mass_assignment`, ...)
- `--source <kind,...|any>`: reads a source of this kind
- `--signal <kind,...|any>`: carries a derived signal (`idor_review`, `ssrf`, `open_redirect`, ...)
- `--validator <kind,...|any>`: carries a validator of this kind

The kinds each bucket can hold are listed in the [AI Context](@/usage/supported/ai_context_coverage/index.md#kinds-by-bucket) reference.

Single-value pattern filters (`<glob|substr>`):
- `--url <glob|substr>`: route URL
- `--path <glob|substr>`: source file path as reported (a relative glob matches from any `/`)
- `--handler <glob|substr>`: handler function name, or handler source file path

Boolean switches (mutually exclusive):
- `--guard` / `--no-guard`: endpoint has or lacks an auth guard (`ai_context.guards`; rate limiting and CSRF checks do not count as a guard)

Exclusion (repeatable):
- `--exclude <filter>=<value>`: drop the endpoints that filter would match. `<filter>` is any filter above without its dashes (`protocol`, `tech`, `url`, `path`, `tag`, `sink`, ...) and `<value>` follows that filter's rules (a comma list is OR, `url`/`path`/`handler` take a glob or a substring, `any` works for the context kinds). An endpoint any `--exclude` matches is dropped, whatever the other filters say.

```bash
noir query --exclude protocol=cli ./app                                     # every language's CLI commands out
noir query --exclude url='/health*' --exclude path='tests/**' --from report.json
noir query --no-guard --exclude sink=any --from report.json                 # unguarded and reaching no sink
```

`--exclude-path` and `--exclude-techs` are different: they are scan flags that keep files or techs out of the analysis, so they only work on a live scan. `--exclude` hides rows of the answer and works with `--from` too.

Views (compare the sources that describe one service):
- `--seen-in <view,...>`: reported by a technology of one of these views
- `--not-seen-in <view,...>`: reported by no technology of these views

Every technology belongs to one view: `code` (framework analyzers, and the schema-generated backends such as Strapi or Supabase), `spec` (OAS, RAML, gRPC, GraphQL SDL, WSDL, ...), `gateway` (nginx, Ingress, Kong, Envoy, Terraform, serverless.yml, ...) or `traffic` (HAR, Burp, Postman, Bruno, `.http` files, ...). `noir list techs` shows each one's view. When two sources report the same method and URL, the optimizer merges them into one endpoint that keeps every technology, and the view filters look at all of them. A comma list is OR, as in the other filters, but repeating `--seen-in` ANDs, because "served by code and also routed by a gateway" is the question these filters exist for.

```bash
noir query --seen-in code --not-seen-in spec ./app        # shadow: served, missing from the spec
noir query --seen-in spec --not-seen-in code ./app        # zombie: in the spec, served by nothing found
noir query --seen-in code --seen-in gateway ./app         # exposed: served and routed by a gateway
```

The match is exact for now: `/orders/{id}` in the spec and `/orders/:id` in the code merge, since Noir normalizes common parameter spellings, but a gateway prefix the service never sees (`/api` in front of `/orders`) keeps the two apart. An endpoint with no technology at all (a hand-written report) matches neither filter.

Pattern matching rules:
- Glob characters (`*`, `?`, `[`): `*` crosses `/` and `{id}` is treated literally. Without glob characters, the pattern is matched as a substring.
- `--param` with `--param-type`: both conditions must be satisfied by the same parameter.
- `any` keyword: for `--sink`, `--source`, `--signal`, and `--validator`, `any` matches any non-empty bucket.
- Warnings on stderr: if a filter value is not present anywhere in the report, Noir prints a warning on stderr with the values that do exist in the report. If context filters (`--guard`, `--sink`, etc.) are used on a report scanned without `--ai-context`, stderr warns that no endpoint carries AI context.

#### Query over a diff

With `--diff-ref <rev>` or `--diff-path <dir>`, `query` scans both sides and filters only the endpoints the change touched, the same set `noir scan --diff-ref` reports. `--change added,changed,removed` picks the categories (a comma list is OR). The default is `added,changed`, the new-side endpoints a reviewer has to look at. `removed` lists old-side endpoints, and the filters apply to them too.

```bash
noir query --diff-ref origin/main --no-guard --sink any .        # added or changed, unguarded, reaching a sink
noir query --diff-ref origin/main --change added --no-guard .     # only the new routes
noir query --diff-path ../old --change removed .                  # what the change took away
```

`--from` also reads a diff report, so one diff scan answers several questions:

```bash
noir scan --diff-ref origin/main --ai-context -f json -o diff.json .
noir query --from diff.json --change added --signal idor_review
```

`--change` without a diff (no diff flag, or `--from` a plain report) is a usage error. `trace` and `reach` do not take a diff: a diff flag there is a usage error too.

`--fail-on-match` turns any query into a CI gate, with or without a diff: exit `3` when at least one row matched (the rows still print, and stderr says how many), `0` when none did, `2` on a usage error. Use it instead of `! noir query ...`, which would also turn a mistyped flag into a passing job. With `--count`, the gate follows the count. `noir scan`'s `--fail-on` is a usage error on the query verbs, so it cannot pass for a gate that never fires.

```bash
noir query --diff-ref origin/main --no-guard --sink any --fail-on-match .
```

### Shared Flags and Exit Codes

Every query verb accepts these options:

| Flag | Description |
|------|-------------|
| `--from <report>` | Read endpoints from a `noir scan -f json` or `-f jsonl` report instead of scanning |
| `-f, --format <fmt>` | Output format: `jsonl` (default), `json`, or `text` (`plain` is accepted as an alias for `text`) |
| `--full` | In `jsonl` and `json`, populate `endpoint` with the full endpoint record alongside `matched_by`, `via`, and `nearest_line`. `trace` already does this by default. In `text`, output remains a single compact line |
| `--limit <n>` | Print at most n rows (must be a positive integer; also limits candidates) |
| `--count` | Print only the number of matches |
| Scan flags | Any `noir scan` flag (`-b`, `--exclude-path`, `--only-techs`, `-t`, `-u`, `--config-file`, ...) is accepted when scanning live without `--from` |

When `--from` is used, passing scan paths or scan flags is a usage error (exit code 2), because nothing is scanned. Global flags (`--no-color`, `-d`, `--verbose`) remain valid with `--from`.

Exit codes follow grep conventions:
- `0`: one or more endpoints matched.
- `1`: nothing matched (trace miss, reach finding no touched endpoints, or query matching zero endpoints).
- `2`: usage error (invalid flag, missing required argument, mutually exclusive flags, non-positive limit, scan arguments passed with `--from`, or unreadable report).
- `3`: `query --fail-on-match` matched one or more endpoints (it then exits `0` when nothing matched).

### Output Row Format

The default compact row (`-f jsonl`) is a projection of the endpoint record, omitting empty buckets:

```json
{"method":"POST","url":"/api/users/{id}","path":"src/routes.go","line":42,"tech":"go_gin",
 "handler":{"name":"updateUser","path":"src/users.go","line":80},
 "params":["id:path","name:json"],"guards":["RequireAuth"],"sinks":["sql"],
 "signals":["idor_review"],"callees":["db.Exec","render"]}
```

- `path:line`: where the route is declared (the first file outside a copy directory when copies were merged; `declarations` counts merged copies when greater than 1).
- `project`: monorepo project directory relative to the scan base (omitted when empty).
- `handler`: where the handler body lives (`name`, `path`, `line`), present when the analyzer resolved the definition.
- `params`: parameters in `name:type` format.
- `guards`: authentication and authorization guards (rate limiting and CSRF excluded).
- `sinks`, `signals`: framework-aware sink kinds and derived security review signals.
- `matched_by`: added by `trace` (`exact`, `pattern`, `wildcard`, `prefix`; `exact_ci`, `pattern_ci`, `wildcard_ci` when only letter case differs, ASP.NET/Express/Koa only, listed last).
- `via`: added by `reach` as a list of evidence items (`route`, `handler`, `callee`, `guard`, `source`, `sink`, `validator`).
- `nearest_line`: added by `reach` when `:LINE` is given.

In text format (`-f text`), each endpoint is printed as a single space-delimited line:

```text
POST /api/users/{id}  src/routes.go:42  go_gin  handler=updateUser@src/users.go:80  guards=RequireAuth  sinks=sql  signals=idor_review
```

An agent skill that teaches these verbs, the scan-once loop and the caveats
to carry lives at [`skills/noir/SKILL.md`](https://github.com/owasp-noir/noir/blob/main/skills/noir/SKILL.md);
copy it into your agent's skills directory.

## List

`noir list` prints the built-in catalogs.

```bash
noir list techs       # supported languages, frameworks, and specs
noir list taggers     # built-in and framework-specific tagger plugins
noir list formats     # every supported output format
noir list techs -f json   # machine-readable; -f accepts text (default), json, yaml
```

## Cache

`noir cache` manages the on-disk LLM response cache at
`~/.config/noir/cache/ai`.

```bash
noir cache info       # location, entry count, total size
noir cache clear      # remove every cached AI response
noir cache purge 30   # remove entries older than 30 days
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

To target a config file other than the default, pass `--config-file
PATH` to `show`, `edit`, or `path`:

```bash
noir config show --config-file ./ci/noir.yaml   # print a specific file
noir config path --config-file ./ci/noir.yaml   # resolve its absolute path
```

`init` always creates the default file and ignores `--config-file`.

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
mkdir -p ~/.local/share/bash-completion/completions
noir completion bash   > ~/.local/share/bash-completion/completions/noir
mkdir -p ~/.config/fish/completions
noir completion fish   > ~/.config/fish/completions/noir.fish
mkdir -p ~/.config/elvish/lib
noir completion elvish > ~/.config/elvish/lib/noir.elv  # then `use noir` from rc.elv
```

The script knows every subcommand. `noir <TAB>` completes the verb list,
and `noir scan -<TAB>` completes scan flags. The Elvish script registers
its completer at `$edit:completion:arg-completer[noir]`. See
[Shell Completion](@/usage/configurations/shell-completion/index.md) for
per-shell setup.

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
| `--no-spinner` | Disable the loading spinner while keeping normal logs                 |
| `-v`, `-V`, `--version` | Print the Noir version and exit                              |
| `-h, --help`   | Show help for the current command                                     |

`--no-color` and `--no-spinner` may sit on either side of the verb:
`noir --no-color list techs` and `noir list techs --no-color` are the
same command. `-v`/`--version` works only before a verb; after one, use
`noir version` (`noir rules update -v` means verbose).

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

When the first argument (after any global flag) is not a known verb, Noir
runs `scan`. CI pipelines, GitHub Actions, Dockerfile entrypoints, and
shell aliases keep working without edits.

Deprecation warnings will land in a later v1.x release. The verb form
becomes mandatory only at v2.x.
