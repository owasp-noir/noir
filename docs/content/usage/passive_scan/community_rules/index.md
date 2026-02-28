+++
title = "Community-Contributed Passive Scan Rules"
description = "Learn how to enhance Noir's passive scanning capabilities by using community-contributed rule sets. This guide shows you where to find these rules and how to add them to your local setup."
weight = 3
sort_by = "weight"

+++

In addition to the default rules that come with Noir, you can also leverage rule sets that have been created and shared by the community. These community-contributed rules can help you find a wider range of potential security issues and can be a great way to benefit from the collective knowledge of the security community.

## Finding Community Rules

The official repository for community-contributed passive scan rules is:

*   **[owasp-noir/noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules)**

This repository contains a collection of rules that have been submitted by Noir users and security researchers.

## How to Use Community Rules

To use the community rules, you need to clone the repository into your local Noir configuration directory. This will add the community rules to the set of rules that Noir uses for passive scanning.

```bash
git clone https://github.com/owasp-noir/noir-passive-rules ~/.config/noir/passive_rules/
```

After you run this command, the community rules will be automatically loaded the next time you run a passive scan with the `-P` or `--passive-scan` flag.

By using community-contributed rules, you can easily expand and enhance Noir's passive scanning capabilities, helping you to find more potential vulnerabilities in your code.
