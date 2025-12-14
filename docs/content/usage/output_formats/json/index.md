+++
title = "JSON and JSONL"
description = "Learn how to get your Noir scan results in JSON or JSONL format. This guide provides examples of both formats and explains how to generate them."
weight = 2
sort_by = "weight"

[extra]
+++

Noir supports JSON and JSONL output formats:

*   **JSON**: Single JSON object containing all results
*   **JSONL**: Each line is a separate JSON object, useful for streaming large datasets

## JSON Output

Generate JSON output:

```bash
noir -b . -f json --no-log
```

Output structure:

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

## JSONL Output

Generate JSONL output:

```bash
noir -b . -f jsonl --no-log
```

Output format (one JSON object per line):

```json
{"url":"/","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/token","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
```
