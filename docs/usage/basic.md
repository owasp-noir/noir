---
title: Basic
parent: Usage
has_children: false
nav_order: 1
layout: page
---

## Basic Run
```bash
noir -b <BASE_PATH>

# noir -b .
# noir -b ./app_directory
```

## Formatting
```bash
noir -b <BASE_PATH> -f <FORMAT>

# You can check the format list with the -h flag.
#     -f FORMAT, --format json         Set output format
#                                       * plain yaml json jsonl markdown-table
#                                       * curl httpie oas2 oas3
#                                       * only-url only-param only-header only-cookie

noir -b . -f json
noir -b . -f yaml
noir -b . -f curl
noir -b . -f only-url
```