+++
title = "Passive Security Scanning"
description = "Learn how to use Noir's passive scanning feature to identify potential security vulnerabilities in your code without actively exploiting them. This guide covers how to run a passive scan and interpret the results."
weight = 5
sort_by = "weight"

[extra]
+++

Noir includes a passive scanning feature that analyzes your code for potential security issues based on a set of predefined rules. Unlike active scanning, which sends test payloads to your application, passive scanning only inspects the source code, making it a safe way to identify vulnerabilities early in the development process.

Passive scanning in Noir works by using regular expressions and string matching to find patterns that indicate common security risks. It comes with a default set of rules, but you can also provide your own custom rules for more targeted scanning.

## How to Run a Passive Scan

To perform a passive scan, use the `-P` or `--passive-scan` flag when running Noir:

```bash
noir -b <BASE_PATH> -P
```

If you want to use a custom set of rules, you can specify the path to your rules file with the `--passive-scan-path` flag:

```bash
noir -b <BASE_PATH> --passive-scan --passive-scan-path /path/to/your/rules.yml
```

### Filtering by Severity Level

You can filter passive scan results by minimum severity level using the `--passive-scan-severity` flag. The available severity levels are:

- `critical`: Only critical severity issues
- `high`: High and critical severity issues (default)
- `medium`: Medium, high, and critical severity issues
- `low`: All severity levels (low, medium, high, and critical)

Examples:

```bash
# Show only critical severity issues
noir -b <BASE_PATH> -P --passive-scan-severity critical

# Show medium severity and above (medium, high, critical)
noir -b <BASE_PATH> -P --passive-scan-severity medium

# Show all issues (default behavior when using 'low')
noir -b <BASE_PATH> -P --passive-scan-severity low
```

The default severity threshold is `high`, which means that without specifying the flag, Noir will detect issues with high and critical severities.

## Understanding the Output

When a passive scan identifies a potential issue, it will produce output similar to this:

```
★ Passive Results:
[critical][hahwul-test][secret] use x-api-key
  ├── extract:   env.request.headers["x-api-key"].as(String)
  └── file: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr:4
```

Here's what each part of the output means:

*   **Severity, Test Name, and Issue Type**: `[critical][hahwul-test][secret]`
    *   `critical`: The severity level of the finding.
    *   `hahwul-test`: The name of the test or rule that triggered the finding.
    *   `secret`: The type of issue, in this case, a hardcoded secret.
*   **Extracted Code**: `extract:   env.request.headers["x-api-key"].as(String)`
    *   This shows the line of code that matched the rule, giving you context for the potential vulnerability.
*   **File Location**: `file: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr:4`
    *   This tells you the exact file and line number where the issue was found, so you can quickly navigate to the code and fix it.

By using passive scanning, you can catch security issues before they make it to production, improving the overall security of your application.
