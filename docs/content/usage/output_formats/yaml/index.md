+++
title = "YAML"
description = "This page explains how to generate scan results in YAML format, which is a human-readable and easy-to-parse option for integrating with other tools or for manual review."
weight = 3
sort_by = "weight"

[extra]
+++

Output scan results in human-readable YAML format for manual inspection or automated processing.

## Usage

Generate YAML output:

```bash
noir -b . -f yaml --no-log
```

## Example Output

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
```
