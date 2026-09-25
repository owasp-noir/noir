+++
title = "YAML"
description = "Generate scan results in human-readable YAML format."
weight = 3
sort_by = "weight"

+++

Output scan results as YAML. It carries the same data as JSON but the indentation-based format makes it easier to skim.

## Usage

```bash
noir scan . -f yaml --no-log
```

## Example Output

The structure mirrors the JSON format: an `endpoints` list with URL, HTTP method, parameters (`param_type` values include `query`, `path`, `header`, `cookie`, `form`, `json`, `file`, `xml`, and related — same vocabulary as [JSON](@/usage/output_formats/json/index.md)), source code paths, and tags for each entry.

```yaml
---
endpoints:
- callees: []
  url: /
  method: GET
  internal: false
  details:
    code_paths:
    - path: spec/functional_test/fixtures/crystal/kemal/src/testapp.cr
      line: 3
    technology: crystal_kemal
  protocol: http
  kind: ""
  tags: []
  params:
  - name: x-api-key
    value: ""
    param_type: header
    tags: []
- callees: []
  url: /query
  method: POST
  internal: false
  details:
    code_paths:
    - path: spec/functional_test/fixtures/crystal/kemal/src/testapp.cr
      line: 17
    technology: crystal_kemal
  protocol: http
  kind: ""
  tags: []
  params:
  - name: my_auth
    value: ""
    param_type: cookie
    tags: []
  - name: query
    value: ""
    param_type: form
    tags: []
passive_results: []
errors: []
```
