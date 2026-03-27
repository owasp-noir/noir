+++
title = "Mermaid Chart"
description = "Generate Mermaid mindmaps to visualize API structure from Noir scan results."
weight = 5
sort_by = "weight"

+++

Visualize API endpoints as a [Mermaid mindmap](https://mermaid-js.github.io/mermaid/#/mindmap) to get a bird's-eye view of your API structure.

## Usage

```bash
noir -b . -f mermaid
```

## Example Output

The mindmap is a tree: the root node represents the API, branches are URL path segments, and leaves show HTTP methods with their parameters (grouped by type: `body`, `headers`, `cookies`).

<details>
    <summary>Mermaid Output</summary>

```
mindmap
  root((API))
    GET
    about
      GET
      GET
      POST
        body
          data
          id
    gems
      GET
    gems_json
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        cookies
          cookie
        body
          query
          sort
    gems_yml
      GET
        cookies
          cookie
        body
          query
          sort
      PUT
        cookies
          cookie
        body
          query
          sort
    path_111
      PUT
    pets
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        body
          name
      param_petId
        GET
          body
            petId
        PUT
          body
            breed
            name
            petId
    shards
      GET
    users
      POST
        body
          email
          name
      param_userId
        GET
          headers
            Authorization
          body
            userId
    v1
      pets
        GET
        POST
        param_petId
          GET
            body
              petId
          PUT
            body
              petId
    zz
      GET
      DELETE
```

</details>

Paste the raw output into the [Mermaid live editor](https://mermaid.live/) to render it interactively, or embed it directly in Markdown files — GitHub, GitLab, and Notion all render Mermaid natively.

{% mermaid() %}
mindmap
  root((API))
    GET
    about
      GET
      GET
      POST
        body
          data
          id
    gems
      GET
    gems_json
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        cookies
          cookie
        body
          query
          sort
    gems_yml
      GET
        cookies
          cookie
        body
          query
          sort
      PUT
        cookies
          cookie
        body
          query
          sort
    path_111
      PUT
    pets
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        body
          name
      param_petId
        GET
          body
            petId
        PUT
          body
            breed
            name
            petId
    shards
      GET
    users
      POST
        body
          email
          name
      param_userId
        GET
          headers
            Authorization
          body
            userId
    v1
      pets
        GET
        POST
        param_petId
          GET
            body
              petId
          PUT
            body
              petId
    zz
      GET
      DELETE
{% end %}

## Tips

- The root node is always labeled `API`.
- HTTP methods, endpoint paths, and parameters are all represented in the mindmap.
- For large APIs, collapse or expand branches in Mermaid-compatible viewers.
