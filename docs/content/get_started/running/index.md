+++
title = "Running Noir"
description = "Basic commands for scanning codebases and configuring output with Noir."
weight = 3
sort_by = "weight"

+++

## Basic Scan

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

```bash
noir --help
```

## Checking Supported Technologies

```bash
noir --list-techs
```

## Output Formats

Default output is table format. Other formats:

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

For a complete list of formats, see the [Output Formats](@/usage/output_formats/_index.md) section.

## Saving Results to a File

```bash
noir -b . -f json -o results.json
```

## Filtering by Technology

Scan only specific frameworks:

```bash
noir -b . --techs rails,django
```

Exclude specific frameworks:

```bash
noir -b . --exclude-techs express
```

## Suppressing Logs

```bash
noir -b . --no-log
```

## Verbose Output

```bash
noir -b . --verbose
```

## Output Customization

### Include File Paths

```bash
noir -b . --include-path
```

### Include Technology Information

```bash
noir -b . --include-techs
```

Combine both:

```bash
noir -b . --include-path --include-techs
```

## Next Steps

- **[Configurations](@/usage/configurations/configuration_file/index.md)**: Set up a config file for default options
- **[Output Formats](@/usage/output_formats/_index.md)**: Explore all available output formats
- **[Passive Scan](@/usage/passive_scan/_index.md)**: Enable passive security scanning
