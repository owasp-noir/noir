---
title: Passive Scan Rule
parent: Passive Scan
has_children: false
nav_order: 1
layout: page
---

## Passive Scan Rule

```yaml
id: rule-id
info:
  name: "The name of the rule"
  author: 
    - "List of authors"
    - "Another author"
  severity: "The severity level of the rule (e.g., critical, high, medium, low)"
  description: "A brief description of the rule"
  reference:
    - "URLs or references related to the rule"

matchers-condition: "The condition to apply between matchers (and/or)"
matchers:
  - type: "The type of matcher (e.g., word, regex)"
    patterns:
      - "Patterns to match"
    condition: "The condition to apply within the matcher (and/or)"

  - type: "The type of matcher (e.g., word, regex)"
    patterns:
      - "Patterns to match"
      - "Another pattern"
    condition: "The condition to apply within the matcher (and/or)"

category: "The category of the rule (e.g., secret, vulnerability)"
techs:
  - "Technologies or frameworks the rule applies to"
  - "Another technology"
```

### Example Rule: Detecting PRIVATE_KEY

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

![](../../../images/advanced/passive_private_key.png)