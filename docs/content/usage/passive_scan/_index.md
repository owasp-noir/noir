+++
title = "Passive Security Scanning"
description = "Rule-based checks that flag potential security issues in source code without sending any traffic."
weight = 5
sort_by = "weight"

+++

Passive scan checks your source code against YAML rules and reports lines that look like security issues (hard-coded secrets, risky calls). It sends no traffic. Rules match with plain strings and regular expressions.

## Usage

Run passive scan:

```bash
noir scan <BASE_PATH> -P
```

To use your own rules, pass `--passive-scan-path`. It takes a **directory**, not a single file: Noir loads every `*.yml` / `*.yaml` below it. The bundled rules are skipped for that run, download included, so a run with `--passive-scan-path` needs neither git nor network. The flag is repeatable; a rule id that arrives from two directories is loaded once.

```bash
noir scan <BASE_PATH> -P --passive-scan-path /path/to/your/rules/
```

### Filtering by Severity

`--passive-scan-severity` sets the lowest severity that is reported:

- `critical`: Critical only
- `high`: High and critical (default)
- `medium`: Medium, high, and critical
- `low`: All levels

Examples:

```bash
# Critical only
noir scan <BASE_PATH> -P --passive-scan-severity critical

# Medium and above
noir scan <BASE_PATH> -P --passive-scan-severity medium

# All issues
noir scan <BASE_PATH> -P --passive-scan-severity low
```

## Output Format

Example output:

```
★ Passive Results:
[critical][aws-access-key][secret] Detect AWS_ACCESS_KEY
  ├── extract: AWS_KEY = "AKIAIOSFODNN7EXAMPLE"
  └── file: ./config/settings.py:1
```

**Output components:**
*   `[critical][aws-access-key][secret]`: severity, rule `id`, rule `category`
*   `Detect AWS_ACCESS_KEY`: rule name (`info.name`)
*   `extract`: Matched code line
*   `file`: File path and line number
