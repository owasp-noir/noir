---
title: YAML
parent: Output Formatting
has_children: false
nav_order: 2
layout: page
---

```bash
noir -b . -f yaml --no-log
```

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
# .......
```