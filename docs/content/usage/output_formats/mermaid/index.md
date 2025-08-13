+++
title = "Mermaid Chart"
description = "Learn how to generate interactive API mindmaps from your Noir scan results using the Mermaid output format. This is a powerful way to visualize your API structure and share it with your team."
weight = 5
sort_by = "weight"

[extra]
+++

The Mermaid output format allows you to visualize your API endpoints as an interactive mindmap. This is especially useful for quickly understanding the structure of your API, identifying available endpoints, and sharing a high-level overview with your team.

Noir can generate a [Mermaid mindmap](https://mermaid-js.github.io/mermaid/#/mindmap) directly from your codebase analysis.

## How to Generate a Mermaid Mindmap

To generate a Mermaid mindmap, use the `-f` or `--format` flag with `mermaid`:

```bash
noir -b . -f mermaid
```

This will output a Mermaid mindmap definition that you can copy and paste into any Mermaid live editor, documentation, or compatible tool.

## Example Mermaid Output

Here is a sample of the output for the `mermaid` format:

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
