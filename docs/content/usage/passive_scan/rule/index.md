+++
title = "Passive Scan Rule"
description = "Create custom passive scan rules using YAML to detect security issues in your codebase."
weight = 1
sort_by = "weight"

+++

```yaml
id: rule-id
info:
  name: "The name of the rule"
  author:
    - "List of authors"
    - "Another author"
  severity: "The severity level of the rule (one of: critical, high, medium, low)"
  description: "A brief description of the rule"
  reference:
    - "URLs or references related to the rule"

matchers-condition: "The condition to apply between matchers (and/or)"
matchers:
  - type: "The type of matcher (one of: word, regex)"
    patterns:
      - "Patterns to match"
    condition: "The condition to apply within the matcher (and/or)"

  - type: "The type of matcher (one of: word, regex)"
    patterns:
      - "Patterns to match"
      - "Another pattern"
    condition: "The condition to apply within the matcher (and/or)"

category: "The category of the rule (e.g., secret, vulnerability)"
techs:
  - "Technologies or frameworks the rule applies to"
  - "Another technology"
```

## Example Rule: Detecting PRIVATE_KEY

```yaml
id: detect-private-key
info:
  name: "Detect PRIVATE_KEY"
  author:
    - "security-team"
  severity: critical
  description: "Detects the presence of PRIVATE_KEY in the code"
  reference:
    - "https://example.com/security-guidelines"

matchers-condition: or
matchers:
  - type: word
    patterns:
      - "PRIVATE_KEY"
      - "-----BEGIN PRIVATE KEY-----"
    condition: or

  - type: regex
    patterns:
      - "PRIVATE_KEY\\s*=\\s*['\"]?[^'\"]+['\"]?"
      - "-----BEGIN PRIVATE KEY-----[\\s\\S]*?-----END PRIVATE KEY-----"
    condition: or

category: secret
techs:
  - '*'
```

<img src="./passive_private_key.png" alt="Passive scan results reporting a critical PRIVATE_KEY finding, quoting the BEGIN PRIVATE KEY line and the file it sits on." width="787" height="286" loading="lazy" decoding="async">

## Notes on rule fields

* `severity` and `matchers[].type` are closed sets. A rule using any other value is invalid and is skipped with a `Skipped invalid passive rule` message, rather than partially applied. `category` is free-form.
* Findings below the minimum severity are filtered out of the report, and the default minimum is `high`. A `severity: medium` or `severity: low` rule produces nothing until you lower the threshold with `--passive-scan-severity`.
* `techs` is result metadata copied onto each finding. It does not gate which files a rule runs against — every loaded rule is evaluated against every scanned file.
* Matchers are evaluated **line by line**: a finding is a single line, and every matcher (and every pattern inside it) has to be satisfied by that one line. A `regex` pattern written to span several lines — `-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----`, for example — therefore never produces a finding on its own; pair it with a `word` matcher on the opening marker.
* `id` must be unique across the whole rule set. A second rule reusing an id is skipped with a `Skipped duplicate passive rule id` message, because the id is what the JSON output and the SARIF `ruleId` identify a finding by.
* A rule file may hold several `---` separated YAML documents; every document is loaded as its own rule.
* A rule whose matchers all fail to compile — a broken `regex` pattern — can never fire, so it is rejected like any other invalid rule instead of being counted as loaded.
