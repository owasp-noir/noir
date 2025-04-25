---
title: Diff Mode
weight: 3
---

Diff mode is a feature that analyzes and compares two source code paths using noir, enabling you to identify newly added, modified, or removed APIs. The base path specified with the `-b` flag serves as the reference point, while the source input provided with the `--diff-path` flag is used for comparison.

```bash
noir -b <BASE_PATH> --diff-path <OLD_APP>

#  DIFF:
#    --diff-path ./app2    Specify the path to the old version of the source code for comparison
```

## Plain output 

In plain output, changes to the APIs are briefly summarized. 

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

## JSON & YAML

In contrast, detailed information is provided in JSON or YAML output. (with `-f=json` or `-f=yaml` )

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

By utilizing this feature, you can build a more efficient pipeline, such as configuring DAST scans to target only added or modified APIs.