+++
title = "JSON and JSONL"
description = "Generate Noir scan results in JSON or JSONL format."
weight = 2
sort_by = "weight"

+++

Noir has two JSON output modes:

*   JSON: one JSON object holding all results
*   JSONL: one JSON object per line, good for streaming and large results

{% mascot(mood="dev") %}
JSON is the format every next stage reads. Pipe it into jq, a script, or an AI auditor's context.
{% end %}

## JSON Output

Use `-f json` to get JSON. Logs go to stderr, so stdout holds only the JSON and is safe to pipe into another tool. Add `--no-log` to hide the logs as well.

```bash
noir scan . -f json --no-log
```

The result is an object with an `endpoints` array, a `passive_results` array, and an `errors` array. Each endpoint has the URL, HTTP method, and parameters (typed as `query`, `path`, `header`, `cookie`, `form`, `json`, `file`, `xml`, and related). It also has the source code location in `details.code_paths`, the analyzer that produced it in `details.technology`, and any security tags from taggers. The sample below was produced with taggers enabled (`-T`), which is what fills the `tags` arrays.

When more than one analyzer finds the same endpoint, for example a Go router and the project's OpenAPI document, Noir merges them into one entry. `details.technology` names the analyzer that won the merge, and `details.technologies` lists every analyzer that contributed, sorted and deduplicated. The list is only emitted when it holds two or more entries, so an endpoint seen by a single analyzer has only `technology`. A consumer that wants every source should read `technologies` when present and fall back to `[technology]` when it is absent.

```json
"details": {
  "code_paths": [
    { "path": "routers/router.go", "line": 42 },
    { "path": "swagger/swagger.json", "line": 1300 }
  ],
  "technology": "go_beego",
  "technologies": ["go_beego", "oas2"]
}
```

A monorepo can serve the same route from two apps, and Noir keeps those as two endpoints. `details.project` names the app each one belongs to: the directory of the nearest build manifest (`pyproject.toml`, `package.json`, `go.mod`, `pom.xml`, ...) above its first source file, relative to the scan base. It is omitted when there is nothing to name, which covers a scan of a single project (its manifest sits at the base itself) and endpoints that come from a specification rather than code, so existing reports are unchanged. `noir query --project services/orders` filters on it.

```json
"details": {
  "code_paths": [{ "path": "mono/services/orders/app.py", "line": 7 }],
  "technology": "python_flask",
  "project": "services/orders"
}
```

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

If an analyzer crashes, Noir logs it, skips it, and continues with the other analyzers. A single file an analyzer cannot read or parse (a file over the parse-time limit, for instance) is skipped the same way, and only that file is lost. `errors` records both. That lets you tell a framework with no endpoints from one that was never analyzed, and a complete scan from one that quietly dropped files:

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

The key is always present. `"errors": []` means every selected analyzer ran to completion over every file it was given.

`-f yaml` carries the same key, and `-f sarif` reports it as `runs[0].invocations[0].executionSuccessful`. Add `--strict` to make a degraded scan exit with code 2, after the report has been written:

```bash
noir scan . -f json --no-log --strict > endpoints.json
```

## JSONL Output

[JSON Lines](https://jsonlines.org/) prints one JSON object per line. Use it with `jq`, or to process a large result line by line without loading it all into memory.

```bash
noir scan . -f jsonl --no-log
```

Each line is a self-contained endpoint object. With `-P`, passive scan findings follow the endpoints, one per line (tell them apart by shape: endpoints have `url` and `method`, findings have `id` and `info`). If an analyzer failed, each failure comes last as its own line with `tech` and `message` (the same entries `errors` holds in JSON). A clean scan writes no such line. Use `--strict` to turn a degraded scan into a non-zero exit code:

```jsonl
{"callees":[],"url":"/","method":"GET","internal":false,"details":{"code_paths":[{"path":"./src/testapp.cr","line":3}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}]}
{"callees":[],"url":"/query","method":"POST","internal":false,"details":{"code_paths":[{"path":"./src/testapp.cr","line":17}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}]}
```
