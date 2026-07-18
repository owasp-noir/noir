+++
title = "Mermaid Chart"
description = "Generate Mermaid mindmaps to visualize API structure from Noir scan results."
weight = 5
sort_by = "weight"

+++

Visualize API endpoints as a [Mermaid mindmap](https://mermaid-js.github.io/mermaid/#/mindmap) to get a bird's-eye view of your API structure.

## Usage

```bash
noir scan . -f mermaid
```

## Example Output

The mindmap is a tree: the root node is the API, branches are URL path segments, and each HTTP method hangs off the path it serves. Parameters under a method are grouped by where they travel in the request — `query`, `body`, `headers`, `cookies`, and `path`. Path parameters also surface as `param_*` branches (so `/users/{user_id}` becomes a `param_user_id` segment), and WebSocket routes are tagged `websocket`.

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

Paste the raw output into the [Mermaid live editor](https://mermaid.live/) to render it interactively, or embed it directly in Markdown files (GitHub, GitLab, and Notion all render Mermaid natively).

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

## Tips

- For large APIs, collapse or expand branches in Mermaid-compatible viewers.
