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
