+++
title = "Passive Security Scanning"
description = "Rule-based checks that flag potential security issues in source code without sending any traffic."
weight = 5
sort_by = "weight"

+++

Analyze code for potential security issues using predefined rules without active exploitation. Uses regular expressions and string matching to identify common security risks.

## Usage

Run passive scan:

```bash
noir scan <BASE_PATH> -P
```

Use custom rules. `--passive-scan-path` takes a **directory**, not a single file: Noir loads every `*.yml` / `*.yaml` below it, and the bundled rules are skipped for that run, download included, so a run with `--passive-scan-path` needs neither git nor network. The flag is repeatable; a rule id that arrives from two directories is loaded once.

```bash
noir scan <BASE_PATH> -P --passive-scan-path /path/to/your/rules/
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
[critical][hahwul-test][secret] use x-api-key
  ├── extract:   env.request.headers["x-api-key"].as(String)
  └── file: ./spec/functional_test/fixtures/crystal/kemal/src/testapp.cr:4
```

**Output components:**
*   `[critical][hahwul-test][secret]`: Severity, rule name, issue type
*   `extract`: Matched code line
*   `file`: File path and line number
