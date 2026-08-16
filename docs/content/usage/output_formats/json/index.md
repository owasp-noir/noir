+++
title = "JSON and JSONL"
description = "Generate Noir scan results in JSON or JSONL format."
weight = 2
sort_by = "weight"

+++

Noir supports two JSON-flavored output modes:

*   **JSON**: Single JSON object containing all results
*   **JSONL**: One JSON object per line, good for streaming and large datasets

## JSON Output

Use `-f json` to get JSON. Adding `--no-log` suppresses log messages so only the JSON hits stdout, which keeps things clean when piping into other tools.

```bash
noir scan . -f json --no-log
```

The result is an object with an `endpoints` array. Each endpoint has the URL, HTTP method, parameters (typed as `cookie`, `form`, `header`, `json`, etc.), source code location in `details.code_paths`, and any security tags from taggers.

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
  ],
  "errors": []
}
```

## Analyzer Failures

A tech analyzer that raises is logged and skipped, and the scan continues with the rest. `errors` records which ones that happened to, so an empty result for a framework can be told apart from a framework that was never analyzed:

```json
{
  "endpoints": [],
  "passive_results": [],
  "errors": [
    { "tech": "go_gin", "message": "Index out of bounds" }
  ]
}
```

The key is always present. `"errors": []` is the positive statement that every selected analyzer ran to completion.

`-f yaml` carries the same key, and `-f sarif` reports it as `runs[0].invocations[0].executionSuccessful`. Add `--strict` to make a degraded scan exit with code 2, after the report has been written:

```bash
noir scan . -f json --no-log --strict > endpoints.json
```

## JSONL Output

[JSON Lines](https://jsonlines.org/) prints one JSON object per line. Ideal for `jq` pipelines or processing large result sets line-by-line without loading everything into memory.

```bash
noir scan . -f jsonl --no-log
```

Each line is a self-contained endpoint object:

```json
{"url":"/","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/token","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
```
