+++
title = "Noir v1.0: Major bump, compat-first"
description = "Why 1.x now, and how the v0 surface stayed intact."
date = "2026-05-24"
tags = ["release", "v1"]
authors = ["hahwul"]
template = "blog_post"
+++

Noir v1.0 is out.

It's been roughly four years since the first commit landed in my personal repo, and now we're cutting it as an official release.

I could have kept extending the 0.x line, but there were two reasons to bump the major.

1. Stability: around v0.30 it reached the point where adding a new framework no longer breaks existing analysis results. Analyzer contracts, output schema, on-disk paths: the core interfaces have settled, and it felt like the right time to call it 1.x.
2. Sub-commands: v0's CLI was flag-only. With more ancillary features coming (cache, rules, config), flags alone were hitting their limits. v1 introduces a verb-based structure: `noir scan / list / cache / config / rules / completion / version / help`.

Outside those two decisions, almost every change was designed around **v0 compatibility**. v0 call shapes like `noir -b ./app -P -f json` route automatically into the `scan` subcommand, and renamed flags keep their old names as silent aliases. The only thing that breaks explicitly is `--ollama` / `--ollama-model`, both deprecated since 2024.

Most v0 scripts run on v1 without modification. That's the whole point of this release.

The full change list and the few items that need migration are collected in the [CHANGELOG v1.0.0](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100).

Upgrades use the same paths as always:

```bash
brew upgrade noir
# or
docker pull ghcr.io/owasp-noir/noir:1.0.0
# or
gh release download v1.0.0 -R owasp-noir/noir
```

Spot a bug or have feedback? File it on [GitHub Issues](https://github.com/owasp-noir/noir/issues). Happy hunting :D
