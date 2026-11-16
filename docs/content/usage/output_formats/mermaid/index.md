+++
title = "Mermaid Chart"
description = "Generate Mermaid mindmaps to visualize API structure from Noir scan results."
weight = 5
sort_by = "weight"

+++

Draw the discovered endpoints as a [Mermaid mindmap](https://mermaid.js.org/syntax/mindmap.html) to see the shape of the API at a glance.

## Usage

```bash
noir scan . -f mermaid
```

## Example Output

The mindmap is a tree: the root node is the API, branches are URL path segments, and each HTTP method hangs off the path it serves. Parameters under a method are grouped by where they travel in the request: `headers`, `cookies`, `query`, `body` (JSON and form fields), and `path`. Path parameters also surface as `param_*` branches (so `/users/{user_id}` becomes a `param_user_id` segment), and WebSocket routes are tagged `websocket`. Names are made safe for Mermaid: characters other than letters, digits and `_` become `_`, and a name that starts with a digit gets a `path_` prefix (`x-api-key` → `x_api_key`, `/1.html` → `path_1_html`).

<details>
    <summary>Mermaid Output</summary>

```
mindmap
  root((API))
    GET
    account
      GET
        headers
          authorization
        cookies
          session
    search
      GET
        query
          page
          q
    users
      POST
        body
          email
          name
      param_user_id
        GET
          query
            verbose
          path
            user_id
        DELETE
          path
            user_id
    ws
      feed
        GET websocket
```

</details>

Paste the output into the [Mermaid live editor](https://mermaid.live/) to render it, or put it in a Markdown file (GitHub, GitLab, and Notion render Mermaid blocks).

{% mermaid() %}
mindmap
  root((API))
    GET
    account
      GET
        headers
          authorization
        cookies
          session
    search
      GET
        query
          page
          q
    users
      POST
        body
          email
          name
      param_user_id
        GET
          query
            verbose
          path
            user_id
        DELETE
          path
            user_id
    ws
      feed
        GET websocket
{% end %}

## Cross-project service graph

With `--ai-context`, a monorepo scan links statically readable outbound HTTP
calls to routes in other projects. If calls are present, Mermaid emits a
`flowchart LR` grouped by project instead of a mindmap:

```bash
noir scan ./monorepo --ai-context -f mermaid
noir trace "GET /checkout" ./monorepo
```

`trace` follows the same candidate edges breadth-first and visits cycles once.
JSON/YAML endpoints contain `calls` (the original sink, URL, method and matching
routes) and `called_by` (caller references and call-site locations). Empty
`matches` means an unmatched call; a missing URL means it could not be read.
Every candidate carries `matched_by`, such as `path_pattern`, `path_template`
or `url_exact`. Several candidates remain visible when the service is ambiguous.
Request-condition variants carry a stable `service_variant` identifier so their
outgoing calls remain separate when a saved report is traced.

These are static candidates, not runtime or data-flow proof. A path-only match
does not identify a host. If both URLs specify an authority it must agree.
Matching requires distinct nonempty `details.project` values, excludes client
stubs and non-HTTP entry points, and does not use an unanchored catch-all alone
as evidence. No call is made to the target service.

Supported call shapes include `fetch`, `axios`, `requests`/`httpx`, Go's
`http.Get`/`http.Post`, and literal-first HTTP client methods. Simple string
concatenation and JavaScript template/Python f-string substitutions can supply
whole path segments. Arbitrary expressions, options-object URLs, unknown base
URLs and config/environment values stay unresolved. Fetch's method is known
for its default call or a single literal `method` option; complex options keep
an unknown method, so every compatible route method remains a candidate.
