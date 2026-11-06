+++
title = "Fill the blanks once: --pvalue across curl, collections, and probes"
description = "One set of parameter placeholders that flows into curl, Postman, OpenAPI, status-code probes, and Burp/ZAP replay."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

If you've ever run `noir scan ./app -f curl`, you know the result: a long list of `/users/{id}?limit=` lines. Great as a map of the app, but you can't paste a single one of them into a terminal and expect a real response.

`-f postman` gives you the same blanks in a different wrapper. `--probe` either sends the literal `{id}` and collects 404s, or, for GET/HEAD/OPTIONS only, quietly fills in `1` or `noir`. Three consumers, each with its own idea of what a parameter should hold.

`--pvalue` settles that in one place. You declare the values once, and the optimizer writes them into every parameter before any formatter or deliverer gets to see the endpoint list. Same scan, same values, no matter where the output ends up.

## The flag

It's repeatable. Each occurrence is `TYPE=VALUE`, or just `VALUE` if you want it applied to every type:

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

`VALUE` itself comes in two shapes:

| Form | Behavior |
| --- | --- |
| `42` | Every parameter of the targeted type |
| `id=42` or `id:42` | Only parameters named `id` |

The substitution happens while the endpoint list is being cleaned up, so it lands ahead of curl, HTTPie, PowerShell, OpenAPI, Postman, JSON and YAML output, and ahead of probing and export too. For the format side see [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.md); for probing see [Delivering Results](@/usage/more_features/deliver/index.md).

## How rules are picked

Type-specific rules win over the global `any` list, so `--pvalue path=…` beats a bare `--pvalue test` for path parameters. Within a type, a rule that names the parameter wins over a catch-all, and the order you pass the flags in doesn't matter:

```bash
# limit → 10; everything else in query → 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=1" \
  --pvalue "query=limit=10"
```

Swap those two lines and you get the same result. If you declare two rules for the same name, the first one wins, but that's a case you rarely want anyway.

## Where the same declaration pays off

### Curl you can actually paste

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

`source` it and go. Path templates are already substituted in the URLs the curl builder emits, so there's no `sed` pass over `{id}` afterwards.

### Postman / OpenAPI for the rest of the team

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

Same `--pvalue` block as the curl run. Reviewers import one collection, CI diffs the OpenAPI against yesterday's, and the placeholders stay identical across formats.

### Live status codes, and optionally a proxy

```bash
# Attach observed status codes; drop the obvious misses
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# Send only reads through Burp/ZAP so the target isn't hit twice as hard
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes`, `--probe` and `--probe-via` all need `-u`.

One thing worth knowing before you probe: without `--pvalue path=…`, Noir only auto-fills path parameters on read-only verbs (GET, HEAD, OPTIONS), using `1` or `noir`. POST, PUT, PATCH and DELETE keep the literal template, so a probe can't turn into `DELETE /users/1` by accident. An explicit `--pvalue path=id=42` removes that guard and applies to every verb, writes included. If that's what you want, fine. If not, keep writes out with `--probe-skip "POST"` or `--probe-skip "DELETE"` until you're ready.

## Put the defaults in a config file

The same keys live in the config file, which saves repeating the flags on every CI job:

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

A `--pvalue` on the command line still wins when a one-off run needs a different id. See [Configuration file](@/usage/configurations/configuration_file/index.md) and [`noir config`](@/usage/cli_commands/_index.md#config).

## Things that trip people up

- **Nameless parameters get nothing.** If an analyzer knows a parameter exists but not what it's called, it's dropped before `--pvalue` runs. You won't see a stray `=42` in the curl output.
- **`body` lands in `json`.** Parameters recorded as `body` are normalized into the buckets the optimizer knows, so `--pvalue json=…` reaches them. For new scripts, use `--pvalue TYPE=VAL` rather than the old `--set-pvalue-*` aliases.
- **Headers follow `-u`.** `--probe-header` and `--pvalue header=…` on probe payloads are aimed at the `-u` host. Endpoints that already carry an absolute host from the source keep that host and don't get those headers. Export destinations you named yourself still do.
- **Secrets don't belong in committed YAML.** Expand them in CI (`--pvalue "header=Authorization=Bearer $TOKEN"`) instead of baking tokens into `ci/noir.yaml`.

## Wrapping up

Discovery output without values is a map with no street numbers. `--pvalue` lets you number them once and reuse the result across curl, collections, OpenAPI, status-code filtering and proxy replay. Be deliberate about write verbs when probing, and once the team agrees on the placeholders, move them into the config file.
