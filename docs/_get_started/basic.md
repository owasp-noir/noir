---
title: Basic
has_children: false
nav_order: 2
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

# noir -b .
# noir -b ./app_directory
```

## Outputs

The output will display endpoints (such as paths, methods, parameters, headers, etc.), and you can specify the output format using flags `-f` or `--format`. If you're curious about the supported formats, please refer to [this](/noir/get_started/output/) document.

![](../../images/get_started/basic.png)

## Usage

```
{% include usage.md %}
```