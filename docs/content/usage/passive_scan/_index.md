+++
title = "Passive Security Scanning"
description = "Learn how to use Noir's passive scanning feature to identify potential security vulnerabilities in your code without actively exploiting them. This guide covers how to run a passive scan and interpret the results."
weight = 5
sort_by = "weight"

[extra]
+++

Analyze code for potential security issues using predefined rules without active exploitation. Uses regular expressions and string matching to identify common security risks.

## Usage

Run passive scan:

```bash
noir -b <BASE_PATH> -P
```

Use custom rules:

```bash
noir -b <BASE_PATH> --passive-scan --passive-scan-path /path/to/your/rules.yml
```

### Filtering by Severity

Filter by severity level using `--passive-scan-severity`:

- `critical`: Critical only
- `high`: High and critical (default)
- `medium`: Medium, high, and critical
- `low`: All levels

Examples:

```bash
# Critical only
noir -b <BASE_PATH> -P --passive-scan-severity critical

# Medium and above
noir -b <BASE_PATH> -P --passive-scan-severity medium

# All issues
noir -b <BASE_PATH> -P --passive-scan-severity low
```

## Output Format

Example output:

```
★ Passive Results:
[critical][hahwul-test][secret] use x-api-key
  ├── extract:   env.request.headers["x-api-key"].as(String)
  └── file: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr:4
```

**Output components:**
*   `[critical][hahwul-test][secret]`: Severity, rule name, issue type
*   `extract`: Matched code line
*   `file`: File path and line number
