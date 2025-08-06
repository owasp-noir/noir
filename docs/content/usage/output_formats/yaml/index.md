+++
title = "YAML Output Format"
description = "This page explains how to generate scan results in YAML format, which is a human-readable and easy-to-parse option for integrating with other tools or for manual review."
weight = 3
sort_by = "weight"

[extra]
+++

YAML (YAML Ain't Markup Language) is a popular data serialization format known for its human-readable syntax. Noir can output its findings in YAML, which is useful for a variety of purposes, from manual inspection to automated processing with other tools.

## How to Generate YAML Output

To get your scan results in YAML format, use the `-f yaml` or `--format yaml` flag when running Noir. It's also a good practice to use the `--no-log` flag to suppress any additional logging information and keep the output clean.

```bash
noir -b . -f yaml --no-log
```

This command will produce a well-structured YAML document containing all the information about the discovered endpoints.

## Example YAML Output

Here is a sample of what the YAML output looks like:

```yaml
endpoints:
  - url: /
    method: GET
    params:
      - name: x-api-key
        value: ""
        param_type: header
        tags: []
    details:
      code_paths:
        - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
          line: 3
    protocol: http
    tags: []
  - url: /query
    method: POST
    params:
      - name: my_auth
        value: ""
        param_type: cookie
        tags: []
      - name: query
        value: ""
        param_type: form
        tags: []
    details:
      code_paths:
        - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
          line: 8
    protocol: http
    tags: []
# ... and so on for all other endpoints
```

As you can see, the YAML output provides a clear and detailed breakdown of each endpoint, including its URL, HTTP method, parameters, and the exact location in the source code where it was found. This makes it easy to integrate Noir's findings into your existing CI/CD pipelines, reporting tools, or any other part of your development workflow.
