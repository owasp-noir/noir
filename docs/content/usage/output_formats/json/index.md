+++
title = "JSON and JSONL Output Formats"
description = "Learn how to get your Noir scan results in JSON or JSONL format. This guide provides examples of both formats and explains how to generate them."
weight = 2
sort_by = "weight"

[extra]
+++

Noir supports both JSON and JSONL as output formats, giving you flexibility in how you process your scan results.

*   **JSON (JavaScript Object Notation)** is a standard, lightweight format that is easy for both humans and machines to understand. It's a great choice for one-off analyses or for integrating with tools that expect a single JSON object.
*   **JSONL (JSON Lines)** is a format where each line is a separate, valid JSON object. This is particularly useful for streaming large amounts of data, as you can process the results one line at a time without having to load the entire file into memory.

## JSON Output

To get your results in JSON format, use the `-f json` or `--format json` flag. It's also a good idea to use `--no-log` to keep the output clean.

```bash
noir -b . -f json --no-log
```

This will produce a single JSON object containing an `endpoints` array:

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

To get your results in JSONL format, use the `-f jsonl` flag:

```bash
noir -b . -f jsonl --no-log
```

This will output a series of JSON objects, each on its own line:

```json
{"url":"/","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[...],"details":{...},"protocol":"http","tags":[]}
{"url":"/token","method":"GET","params":[...],"details":{...},"protocol":"http","tags":[]}
```
