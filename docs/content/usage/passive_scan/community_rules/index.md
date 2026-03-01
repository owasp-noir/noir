+++
title = "Community-Contributed Passive Scan Rules"
description = "Use community-contributed passive scan rules with Noir."
weight = 3
sort_by = "weight"

+++

Beyond the default rules, you can use community-contributed rules to detect a wider range of security issues.

## Repository

*   **[owasp-noir/noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules)**

## Installation

Clone the repository into your Noir configuration directory:

```bash
git clone https://github.com/owasp-noir/noir-passive-rules ~/.config/noir/passive_rules/
```

Community rules are automatically loaded on the next passive scan (`-P`).
