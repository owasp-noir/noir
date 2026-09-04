+++
title = "JSON and JSONL"
description = "Generate Noir scan results in JSON or JSONL format."
weight = 2
sort_by = "weight"

+++

Noir supports two JSON-flavored output modes:

*   **JSON**: Single JSON object containing all results
*   **JSONL**: One JSON object per line, good for streaming and large datasets

{% mascot(mood="dev") %}
JSON is the format every next stage reads. Pipe it into jq, a script, or an AI auditor's context.
{% end %}

## JSON Output

Use `-f json` to get JSON. Adding `--no-log` suppresses log messages so only the JSON hits stdout, which keeps things clean when piping into other tools.

```bash
noir scan . -f json --no-log
```

The result is an object with an `endpoints` array, a `passive_results` array, and an `errors` array. Each endpoint has the URL, HTTP method, parameters (typed as `cookie`, `form`, `header`, `json`, etc.), source code location in `details.code_paths`, the analyzer that produced it in `details.technology`, and any security tags from taggers. The sample below was produced with taggers enabled (`-T`), which is what fills the `tags` arrays.

```json
{
  "endpoints": [
    {
      "callees": [],
      "url": "/query",
      "method": "POST",
      "internal": false,
      "details": {
        "code_paths": [
          {
            "path": "spec/functional_test/fixtures/crystal/kemal/src/testapp.cr",
            "line": 17
          }
        ],
        "technology": "crystal_kemal"
      },
      "protocol": "http",
      "kind": "",
      "tags": [],
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
          "tags": []
        }
      ]
    },
    {
      "callees": [],
      "url": "/token",
      "method": "GET",
      "internal": false,
      "details": {
        "code_paths": [
          {
            "path": "spec/functional_test/fixtures/crystal/kemal/src/testapp.cr",
            "line": 22
          }
        ],
        "technology": "crystal_kemal"
      },
      "protocol": "http",
      "kind": "",
      "tags": [
        {
          "name": "oauth",
          "description": "Suspected OAuth endpoint for granting 3rd party access.",
          "tagger": "Oauth"
        }
      ],
      "params": [
        {
          "name": "client_id",
          "value": "",
          "param_type": "form",
          "tags": []
        },
        {
          "name": "redirect_url",
          "value": "",
          "param_type": "form",
          "tags": [
            {
              "name": "ssrf",
              "description": "This parameter may be vulnerable to Server Side Request Forgery (SSRF) attacks.",
              "tagger": "Hunt"
            }
          ]
        },
        {
          "name": "grant_type",
          "value": "",
          "param_type": "form",
          "tags": []
        }
      ]
    }
  ],
  "passive_results": [],
  "errors": []
}
```

## Analyzer Failures

A tech analyzer that raises is logged and skipped, and the scan continues with the rest. So is a single file the analyzer cannot read or parse — a file over the parse-time ceiling, for instance — which costs only itself rather than the run. `errors` records both, so an empty result for a framework can be told apart from a framework that was never analyzed, and a complete scan from one that quietly dropped files:

```json
{
  "endpoints": [],
  "passive_results": [],
  "errors": [
    { "tech": "go_gin", "message": "Index out of bounds" },
    { "tech": "rust_axum", "message": "skipped 2 files: src/gen.rs, src/vendor.rs; first error: ts_parser_parse_string returned null (timed out after 10000ms, or out of memory)" }
  ]
}
```

Skipped files are tallied per tech rather than listed one entry each, with up to five example paths, so a broken checkout cannot flood the report.

The key is always present. `"errors": []` is the positive statement that every selected analyzer ran to completion over every file it was given.

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

```jsonl
{"callees":[],"url":"/","method":"GET","internal":false,"details":{"code_paths":[{"path":"src/testapp.cr","line":3}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}]}
{"callees":[],"url":"/query","method":"POST","internal":false,"details":{"code_paths":[{"path":"src/testapp.cr","line":17}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}]}
```
