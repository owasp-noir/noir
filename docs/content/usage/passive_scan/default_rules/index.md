+++
title = "Default Passive Scan Rules"
description = "Learn where Noir stores its default passive scanning rules and how you can extend them with your own custom rules to enhance your security analysis."
weight = 2
sort_by = "weight"

[extra]
+++

Noir comes with a set of default rules for its passive scanning feature. These rules are curated by the Noir team to detect common security vulnerabilities and are automatically updated when you update Noir.

## Rule Locations

The default rules are stored in a specific directory depending on your operating system:

| OS      | Path                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

When you run a passive scan with the `-P` or `--passive-scan` flag, Noir looks for rules in this directory.

## Customizing the Rules

While the default rules are a great starting point, you may want to add your own rules to look for issues that are specific to your organization or application. To do this, you can simply create a new YAML rule file and place it in the same directory as the default rules.

Any `.yml` or `.yaml` file you add to this directory will be automatically loaded and used by the passive scanner the next time you run it. This allows you to easily extend and customize Noir's passive scanning capabilities to meet your specific needs without having to modify the default rule set.

