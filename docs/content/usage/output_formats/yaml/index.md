+++
title = "YAML"
description = "Generate scan results in human-readable YAML format."
weight = 3
sort_by = "weight"

+++

Output scan results as YAML. It carries the same data as JSON but the indentation-based format makes it easier to skim.

## Usage

```bash
noir -b . -f yaml --no-log
```

## Example Output

The structure mirrors the JSON format: an `endpoints` list with URL, HTTP method, parameters, source code paths, and tags for each entry.

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
