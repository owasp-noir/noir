+++
title = "Fill the blanks once: --pvalue across curl, collections, and probes"
description = "One set of parameter placeholders that flows into curl, Postman, OpenAPI, status-code probes, and Burp/ZAP replay."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

You run `noir scan ./app -f curl` and get a wall of `/users/{id}?limit=`. Useful as a map. Useless as a request.

`-f postman` is the same blank forms in a different envelope. `--probe` either 404s on the literal `{id}` or, for GET/HEAD/OPTIONS only, quietly stuffs in `1` / `noir`. Three sinks, three opinions about one parameter.

`--pvalue` is how you settle that once. Declare the placeholders; the optimizer writes them into every param *before* any formatter or deliverer runs. Same scan. Same values. Every sink.

## The flag

Repeatable. Each hit is `TYPE=VALUE`, or a bare `VALUE` that hits every type:

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

`VALUE` comes in two shapes:

| Form | Behavior |
| --- | --- |
| `42` | Every parameter of the targeted type |
| `id=42` or `id:42` | Only parameters named `id` |

This runs when the endpoint list is cleaned — ahead of curl / HTTPie / PowerShell / OpenAPI / Postman / JSON / YAML and ahead of probe/export. One declaration, every consumer. Format side: [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.md). Probe side: [Delivering Results](@/usage/more_features/deliver/index.md).

## Order bites

Matching is first-hit. Type-specific rules beat the global `any` list, so `--pvalue path=…` wins over a bare `--pvalue test` for path params.

Inside one type, a catch-all matches *every* name. Named overrides go first:

```bash
# limit → 10; everything else in query → 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=limit=10" \
  --pvalue "query=1"
```

Swap those two lines and `limit` is `1` too — the catch-all fired first. A few doc examples still show the catch-all first; that order is wrong for this matcher. Named rules, then the type-wide default.

## Same declaration, three places it pays off

### Curl you can actually paste

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

`source` it. Path templates are already substituted in the URL the curl builder emits — no `sed` pass over `{id}`.

### Postman / OpenAPI for everyone else

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

Identical `--pvalue` block. Reviewers import one collection; CI diffs the OpenAPI against yesterday's. Placeholders do not drift between formats.

### Live status codes, optional proxy replay

```bash
# Attach observed codes; drop the obvious misses
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# Read traffic through Burp/ZAP without doubling load on the target
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes`, `--probe`, and `--probe-via` all want `-u`.

Path fill on probes has a safety rail you will notice the hard way: without `--pvalue path=…`, Noir auto-fills only read-only verbs (GET, HEAD, OPTIONS) with `1` / `noir`. POST / PUT / PATCH / DELETE keep the literal template, so a probe cannot become `DELETE /users/1` by accident. An explicit `--pvalue path=id=42` applies to *every* verb, writes included. Mean that, or park writes behind `--probe-skip "POST"` / `--probe-skip "DELETE"` until you do.

## Park the defaults in config

Same keys, no flag soup on every CI job:

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

CLI `--pvalue` still wins when a one-off needs a different id. [Configuration file](@/usage/configurations/configuration_file/index.md) · [`noir config`](@/usage/cli_commands/_index.md#config).

## What bites you

- **Nameless params get nothing.** If an analyzer knows a hole exists but not its name, that hole is dropped before `--pvalue` runs. You will not see a stray `=42` in curl.
- **`body` lands in `json`.** Params recorded as `body` are normalized into the buckets the optimizer knows, so `--pvalue json=…` reaches them. Prefer v1 `--pvalue TYPE=VAL` over the old `--set-pvalue-*` aliases in new scripts.
- **Headers follow `-u`.** `--probe-header` and `--pvalue header=…` on probe payloads target the `-u` host. Endpoints that already carry an absolute host from source keep it; probe headers aimed at `-u` are withheld from those. Export destinations you named yourself still get the header.
- **Secrets do not belong in committed yaml.** Expand in CI (`--pvalue "header=Authorization=Bearer $TOKEN"`). Do not bake tokens into `ci/noir.yaml`.

## Wrap

Discovery without values is a map with no street numbers. Number them once with `--pvalue`, reuse across curl, collections, OpenAPI, status-code filters, and proxy replay. Named overrides before catch-all rules. Write verbs on purpose. Defaults in the config file when the team agrees.
