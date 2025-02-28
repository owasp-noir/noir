---
title: JSON & JSONL
parent: Output Formatting
has_children: false
nav_order: 1
layout: page
---

# JSON & JSONL

Noir can output results in JSON and JSONL formats. JSON is a lightweight data interchange format that is easy for humans to read and write, and easy for machines to parse and generate. JSONL is a format where each JSON object is on a separate line, making it suitable for streaming and processing large datasets.

## JSON
```bash
noir -b . -f json --no-log
```

```json
{
  "endpoints": [
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
  ]
}
```

## JSONL

```bash
noir -b . -f jsonl --no-log
```

```json
{"url":"/","method":"GET","params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":3}]},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":8}]},"protocol":"http","tags":[]}
{"url":"/token","method":"GET","params":[{"name":"client_id","value":"","param_type":"form","tags":[]},{"name":"redirect_url","value":"","param_type":"form","tags":[]},{"name":"grant_type","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":13}]},"protocol":"http","tags":[]}
{"url":"/socket","method":"GET","params":[],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":19}]},"protocol":"ws","tags":[]}
{"url":"/1.html","method":"GET","params":[],"details":{"code_paths":[]},"protocol":"http","tags":[]}
{"url":"/2.html","method":"GET","params":[],"details":{"code_paths":[]},"protocol":"http","tags":[]}
```