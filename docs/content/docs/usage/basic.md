---
title: Basic
has_children: false
weight: 1
layout: page
---

With noir, you can view the help documentation using the `-h` or `--help` flags.

```bash
noir -h 
```

## Requirements arguments

By default, you need to specify the source code directory to analyze using the `-b` or `--base-path` flag.

```bash
noir -b <BASE_PATH>

# noir -b .s
# noir -b ./app_directory
```

## Outputs

```bash
noir -b <BASE_PATH> -f <FORMAT>

# You can check the format list with the -h flag.
#     -f FORMAT, --format json         Set output format
#                                       * plain yaml json jsonl markdown-table
#                                       * curl httpie oas2 oas3
#                                       * only-url only-param only-header only-cookie

```

| Format          | Description                                                                 |
|-----------------|-----------------------------------------------------------------------------|
| plain           | Outputs the results in plain text format.                                   |
| yaml            | Outputs the results in YAML format.                                         |
| json            | Outputs the results in JSON format.                                         |
| jsonl           | Outputs the results in JSON Lines format, where each line is a JSON object. |
| markdown-table  | Outputs the results in a Markdown table format.                             |
| curl            | Outputs the results as curl commands.                                       |
| httpie          | Outputs the results as httpie commands.                                     |
| oas2            | Outputs the results in OpenAPI Specification v2 format.                     |
| oas3            | Outputs the results in OpenAPI Specification v3 format.                     |
| only-url        | Outputs only the URLs found in the analysis.                                |
| only-param      | Outputs only the parameters found in the analysis.                          |
| only-header     | Outputs only the headers found in the analysis.                             |
| only-cookie     | Outputs only the cookies found in the analysis.                             |