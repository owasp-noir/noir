+++
title = "Community-Contributed Passive Scan Rules"
description = "How community-contributed passive scan rules are distributed and how to contribute or use your own rule sets."
weight = 3
sort_by = "weight"

+++

Passive scan rules, both the defaults and community contributions, live in a single repository:

*   **[owasp-noir/noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules)**

You do not need to install anything manually: when passive scanning is enabled (`-P`), Noir clones this repository to `~/.config/noir/passive_rules/` on first run and notifies you when it falls behind. Add `--passive-scan-auto-update` to pull the latest rules on startup, or run `git pull` in that directory yourself.

## Contributing rules

To share a rule with the community, open a pull request against [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules). Once merged, every Noir user picks it up through the normal rule update flow. See [Passive Scan Rule](../rule/) for the rule format.

## Using third-party or custom rule sets

To run a rule set from somewhere else (a private repository, a local directory), point Noir at it with `--passive-scan-path`:

```bash
noir scan /app -P --passive-scan-path ./my-rules/
```

This replaces the bundled rules for that run. The flag can be repeated to load multiple directories or files. Alternatively, drop extra `.yml`/`.yaml` files into `~/.config/noir/passive_rules/`. Everything in that directory is loaded recursively.
