+++
title = "Default Rules"
description = ""
weight = 2
sort_by = "weight"

[extra]
+++

The default rules are stored in the following paths based on your operating system:

| OS | Path |
|---|---|
| MacOS: | `~/.config/noir/passive_rules/` |
| Linux: | `~/.config/noir/passive_rules/` |
| Windows: | `%APPDATA%\noir\passive_rules\` |

When using the `-P` (`--passive-scan`) flag, Noir references the rules stored in these paths. These rules are managed by the Noir team, ensuring they are up-to-date and effective.

However, if you wish to add your own custom rules, you can place them in the respective directory for your operating system. This allows you to extend the functionality of the passive scan to meet your specific needs.
