+++
title = "Fill the blanks once: --pvalue across curl, collections, and probes"
description = "One set of parameter placeholders that flows into curl, Postman, OpenAPI, status-code probes, and Burp/ZAP replay."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

Noir's job is discovery. It finds routes, methods, and parameters. What it does *not* invent is a value you can paste into a request and hit a real server with.

That gap shows up the moment you leave plain output. `-f curl` prints `/users/{id}` with an empty query. `-f postman` ships a collection full of blank fields. `--probe` against a live app either 404s on the literal template or, for read-only verbs, quietly substitutes `1` / `noir`. Three consumers, three different stories about the same parameter.

`--pvalue` is the fix. You declare the placeholders once; the optimizer writes them into every param before any format or deliverer runs. Same scan, same values, every sink.

## What --pvalue actually does

The flag is repeatable. Each occurrence is `TYPE=VALUE`, or a bare `VALUE` that applies to every type:

```bash
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  --pvalue "header=Authorization=Bearer replace-me"
```

| `TYPE` | Scope |
| --- | --- |
| `any` (or omit the type) | Every parameter type |
| `query` / `form` / `json` / `header` / `cookie` / `path` | That bucket only |

`VALUE` itself has two shapes:

| Form | Behavior |
| --- | --- |
| `42` | Used for every parameter of the targeted type |
| `id=42` or `id:42` | Used only for parameters named `id` |

The optimizer applies these rules when it cleans the endpoint list, before output builders and before probe/export. That is why the same `--pvalue` line affects curl, HTTPie, PowerShell, OpenAPI, Postman, JSON/YAML, and live probes in one pass. See [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.md) for the format side, and [Delivering Results](@/usage/more_features/deliver/index.md) for probe behavior.

## Rule order matters

Matching is first-hit. Within a type, type-specific rules are checked before the global `any` list, which is why `--pvalue path=…` beats a bare `--pvalue test` for path params.

Inside one type, though, a catch-all matches *every* name. Put the named overrides first:

```bash
# limit gets 10; every other query param gets 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=limit=10" \
  --pvalue "query=1"
```

Flip those two lines and `limit` also becomes `1`, because the catch-all rule fires first. The docs examples that show the catch-all first are the wrong order for this matcher; named rules before the type-wide default is the reliable shape.

## Three workflows that share one declaration

### 1. Runnable curl for manual triage

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

Paste or `source` the file and you have concrete requests. Path templates are already substituted in the URL the curl builder emits, so you are not hand-editing `{id}` on every line.

### 2. Postman / OpenAPI for the rest of the team

```bash
noir scan ./api -f postman -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  --pvalue "header=Authorization=Bearer replace-me" \
  -o /tmp/api.postman.json

noir scan ./api -f oas3 -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  -o /tmp/api.openapi.json
```

Same `--pvalue` block as the curl run. Reviewers import one collection; CI diffs the OpenAPI against the previous commit. The placeholders stay stable across formats, which is the whole point.

### 3. Live validation with status codes (and optional proxy replay)

```bash
# Attach observed status codes; drop obvious misses
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# Or push read traffic through Burp/ZAP without doubling the target load
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes` and `--probe` / `--probe-via` all need `-u`. Path filling for probes has an extra safety rail: without `--pvalue path=…`, Noir only auto-fills read-only verbs (GET, HEAD, OPTIONS) with `1` / `noir`. POST/PUT/PATCH/DELETE keep the literal template so a probe cannot turn into `DELETE /users/1` by accident. An explicit `--pvalue path=id=42` applies to every verb, including writes. Use that deliberately, or keep write methods behind `--probe-skip "POST"` / `--probe-skip "DELETE"` until you mean it.

## Team defaults without pasting flags

The same keys live in the config file, so a shared `ci/noir.yaml` can carry the project's placeholder policy:

```yaml
url: "https://staging.example.com"
format: "json"
status_codes: true
exclude_codes: "404,502"
set_pvalue_path:
  - "id=42"
  - "slug=demo"
set_pvalue_query:
  - "limit=10"
  - "1"
set_pvalue_header:
  - "X-Debug-Tenant=noir-ci"
```

```bash
noir config init
noir scan ./api --config-file ./ci/noir.yaml
```

CLI `--pvalue` still overrides the file when a one-off needs a different id. See [Using a Configuration File](@/usage/configurations/configuration_file/index.md) and [`noir config`](@/usage/cli_commands/_index.md#config).

## Caveats worth remembering

- **Empty names never get a value.** Analyzers that know a param exists but not its name drop that hole before `--pvalue` runs. You will not see a mysterious `=42` in curl.
- **`body` vs `json`.** Params recorded as `body` are normalized into the canonical buckets the optimizer understands, so `--pvalue json=…` reaches them. Prefer the v1 `--pvalue TYPE=VAL` form over the old `--set-pvalue-*` aliases in new scripts.
- **Headers on foreign hosts.** `--probe-header` (and values you put in `--pvalue header=…` for probe payloads) are for the `-u` target. Endpoints that already carry their own absolute host from source keep that host; probe headers aimed at `-u` are withheld from it. Export destinations you named yourself still get the header.
- **Do not put secrets in committed config.** Prefer env-expanded flags in CI (`--pvalue "header=Authorization=Bearer $TOKEN"`) over baking tokens into `ci/noir.yaml`.

## Short wrap

Discovery without values is a map with no street numbers. `--pvalue` is how you number them once and reuse the same numbering in curl, collections, OpenAPI, status-code filters, and proxy replay. Put named overrides before catch-all rules, keep write verbs explicit, and park the defaults in a config file when the team agrees on the placeholders.
