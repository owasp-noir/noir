---
title: Diff Mode
has_children: false
nav_order: 4
layout: page
---

```bash
noir -b <BASE_PATH> --diff-paht <OLD_APP>

#  DIFF:
#    --diff-path ./app2    Specify the path to the old version of the source code for comparison
```

## Plain output 

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
[I] Removed: /posts/1 GET
[I] Removed: /posts POST
[I] Removed: /posts/1 PUT
[I] Removed: /posts/1 DELETE
```

## JSON

```json
{
  "added": [
    {
      "url": "/",
      "method": "GET",
      "params": [
        {
          "name": "query",
          "value": "",
          "param_type": "query",
          "tags": []
        },
        {
          "name": "cookie1",
          "value": "",
          "param_type": "cookie",
          "tags": []
        },
        {
          "name": "cookie2",
          "value": "",
          "param_type": "cookie",
          "tags": []
        },
        {
          "name": "x-api-key",
          "value": "",
          "param_type": "header",
          "tags": []
        },
        {
          "name": "X-API-Key",
          "value": "",
          "param_type": "header",
          "tags": []
        },
        {
          "name": "name",
          "value": "",
          "param_type": "query",
          "tags": []
        },
        {
          "name": "abcd_token",
          "value": "",
          "param_type": "cookie",
          "tags": []
        }
      ],
      "details": {
        "code_paths": [
          {
            "path": "./spec/functional_test/fixtures/rust_rocket/src/main.rs",
            "line": 3
          }
        ]
      },
      "protocol": "http",
      "tags": []
    }
    ....
  ],
  "removed": [
    {
      "url": "/secret.html",
      "method": "GET",
      "params": [],
      "details": {
        "code_paths": [
          {
            "path": "./spec/functional_test/fixtures/ruby_rails/public/secret.html"
          }
        ]
      },
      "protocol": "http",
      "tags": []
    }
    ....
  ],
  "changed": []
}
```