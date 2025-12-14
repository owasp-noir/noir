+++
title = "Mermaid Chart"
description = "Learn how to generate interactive API mindmaps from your Noir scan results using the Mermaid output format. This is a powerful way to visualize your API structure and share it with your team."
weight = 5
sort_by = "weight"

[extra]
+++

Visualize API endpoints as an interactive [Mermaid mindmap](https://mermaid-js.github.io/mermaid/#/mindmap) for understanding API structure.

## Usage

Generate mindmap:

```bash
noir -b . -f mermaid
```

Copy output to Mermaid live editor or compatible tools.

## Example Output

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

You can visualize this mindmap by pasting the output into any [Mermaid live editor](https://mermaid.live/) or embedding it in your documentation.

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

## Why Use Mermaid Mindmaps?

- **Visualize API structure** at a glance
- **Share endpoint maps** with your team or stakeholders
- **Quickly spot missing or duplicate endpoints**
- **Integrate with docs**: Mermaid is supported by many documentation tools

## Tips

- The root node is always labeled `API` for clarity.
- HTTP methods (GET, POST, etc.), endpoint paths, and parameters are all represented in the mindmap.
- For large APIs, you can collapse or expand branches in Mermaid-compatible viewers for easier navigation.

By using the Mermaid output, you can instantly turn your Noir scan results into a visual, navigable map of your API surface.
