+++
title = "Noir v1.0 — Major bump, compat-first"
description = "Why 1.x now, and how the v0 surface stayed intact."
date = "2026-05-23"
tags = ["release", "v1"]
authors = ["hahwul"]
template = "blog_post"
+++

Noir v1.0 is out.

Two reasons drove the major bump.

**First, maturity.** Around v0.30 the rate of framework-level surprises dropped to where adding a new analyzer no longer threatens existing scans. Analyzer contracts, output schema, on-disk paths — the core interfaces have settled. It started feeling honest to call the line "1.x".

**Second, sub-commands.** v0's CLI was flag-only. As ancillary features (cache, rules, config) kept growing, the flag-only shape ran out of expressive room. v1 introduces a verb layer: `noir scan / list / cache / config / rules / completion / version / help`.

Outside those two decisions, almost every change was designed around **v0 compatibility**. v0 call shapes like `noir -b ./app -P -f json` route automatically into the `scan` subcommand; renamed flags keep their old names as silent aliases. The only thing that breaks explicitly is `--ollama` / `--ollama-model`, both deprecated since 2024.

Most v0 scripts run on v1 without touching a single line. That's the message of this release.

Full change list and the few items that need migration are in the [CHANGELOG v1.0.0](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100).

Upgrades use the same paths as always:

```bash
brew upgrade noir
# or
docker pull ghcr.io/owasp-noir/noir:1.0.0
# or
gh release download v1.0.0 -R owasp-noir/noir
```

Feedback and regression reports welcome on [GitHub Issues](https://github.com/owasp-noir/noir/issues). Happy hunting.
