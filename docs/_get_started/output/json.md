---
title: JSON
parent: Output Formatting
has_children: false
nav_order: 1
layout: page
---

```bash
noir -b . -f json --no-log
```

```json
{
    "url": "https://testapp.internal.domains/query",
    "method": "POST",
    "params": [
      {
        "name": "my_auth",
        "value": "",
        "param_type": "cookie",
        "tags": []
      },
      {
        "name": "query",
        "value": "",
        "param_type": "form",
        "tags": [
          {
            "name": "sqli",
            "description": "This parameter may be vulnerable to SQL Injection attacks.",
            "tagger": "Hunt"
          }
        ]
      }
    ],
    "details": {
      "code_paths": [
        {
          "path": "spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
          "line": 8
        }
      ]
    },
    "protocol": "http",
    "tags": []
}
```