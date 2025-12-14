+++
title = "Running Noir"
description = "Learn the basic commands to get started with Noir. This guide shows you how to run a scan on a directory and view the available command-line options."
weight = 3
sort_by = "weight"

[extra]
+++

## Basic Scan

Analyze a codebase using the `-b` or `--base-path` flag:

Scan current directory:

```bash
noir -b .
```

Scan subdirectory:

```bash
noir -b ./my_app
```

![](./running.png)

## Viewing Help Information

View all available commands and flags:

```bash
noir -h
```

## Checking Supported Technologies

List supported languages and frameworks:

```bash
noir --list-techs
```

## Output Formats

Default output is table format. Available formats:

### JSON Output

```bash
noir -b . -f json
```

### YAML Output

```bash
noir -b . -f yaml
```

### OpenAPI Specification

```bash
noir -b . -f oas3
```

## Suppressing Logs

Clean output without log messages:

```bash
noir -b . --no-log
```

## Verbose Output

Detailed information output:

```bash
noir -b . --verbose
```
