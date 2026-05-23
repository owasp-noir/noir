+++
title = "Noir v1.0 — Major bump, compat-first"
description = "Why 1.x now, what we broke on purpose, what we kept untouched, and a production bug from the RC."
date = "2026-05-23"
tags = ["release", "v1"]
authors = ["hahwul"]
template = "blog_post"
+++

Noir v1.0 is out.

Two reasons drove the major bump.

**First, maturity.** Noir's analyzer, tagger, and passive-scan surface have been expanding fast since the first commit, but somewhere around v0.30 the rate of framework-level surprises dropped to where adding a new analyzer no longer threatens existing scans. Analyzer contracts, output schema, on-disk paths — the core interfaces have settled. It started feeling honest to call the line "1.x".

**Second, sub-commands.** v0's CLI was flag-only. Everything sat under one `noir [flags]` surface — cache management, rules management, config, completion generation, all piled together. As ancillary features kept growing, the flag-only shape was running out of expressive room. v1 introduces a verb layer: `noir scan / list / cache / config / rules / completion / version / help`.

Outside those two decisions, **almost every change was designed around v0 compatibility**.

## Your v0 scripts still work

v0 call shapes like `noir -b ./app -P -f json -o out.json` run unchanged on v1. The router watches for a leading flag and automatically routes the call into the `scan` subcommand. CI pipelines, GitHub Actions, Dockerfile entrypoints, shell aliases — wherever you've embedded the v0 form, it keeps working.

Renamed flags keep their old names as silent aliases:

- `--set-pvalue VAL` (plus the six type variants — header/cookie/query/form/json/path) — aliased to the new `--pvalue TYPE=VAL`
- `--include-path` / `--include-techs` / `--include-callee` — aliased to the new `--include LIST`
- `--list-techs`, `--list-taggers`, `--build-info`, `--help-all`, `-v` / `--version`, `--generate-completion SHELL` — rewritten to the matching subcommand at the router layer

The only thing that breaks explicitly is `--ollama URL` / `--ollama-model NAME`. Both have been deprecated since 2024; v1 rejects them with a one-line migration hint (`--ai-provider ollama [--ai-model NAME]`).

## A production bug from the RC

One of the more interesting catches during the RC pass was in `--send-es URL` (Elasticsearch delivery): every call was shipping an empty POST body to ES.

The cause was a signature quirk in Crystal's HTTP client, Crest. `Crest::Request.execute(method: :post, body: ..., json: true)` doesn't actually recognize `body:` as a keyword — it gets swallowed by `**options` and silently dropped. The real body slot is `form:`, and combined with `json: true` it forwards the raw String through as-is.

The code read `body: body`. The compiler was happy. HTTP requests returned 200. Logs looked normal. Elasticsearch just received zero bytes on every push. With no spec covering the delivery layer, nobody noticed — it had been quietly broken for a release cycle. One-character fix (`body:` → `form:`), plus a regression spec that spins up an in-process HTTP server and actually checks that the body arrives.

Several more latent bugs surfaced in the Deliver, OutputBuilder, Tagger, PassiveScan, and ConfigInitializer layers over the same pass. They all came out as a side effect of laying down specs on code paths that had been running without coverage. Full list is in the [CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100).

## Docker / GitHub Action got a cleanup too

Previously the GitHub Action shipped a sibling `github-action/Dockerfile` that started with `FROM ghcr.io/owasp-noir/noir:1.0.0` + apt-installed jq and got rebuilt on every workflow call. Every major release required manually bumping that hardcoded `1.0.0`, and the apt step paid for itself on every invocation.

In v1:

- One unified `Dockerfile` (jq, `entrypoint.sh`, GH Actions labels all included)
- `action.yml` is now `using: composite` — pulls and runs the pre-built ghcr image instead of rebuilding
- Image tag is resolved from `github.action_ref` (`@v1.0.0` → `ghcr.io/owasp-noir/noir:1.0.0`)
- The image bakes a `noir-passive-rules` snapshot, so `-P` works inside the container without git or network

The Action's `with:` inputs and outputs are unchanged. From the user seat, only the first invocation feels faster.

## JSON output stays compatible

Endpoint JSON gains two fields: `callees` (1-hop call graph) and `ai_context` (populated only when `--ai-context` is enabled). Every existing field keeps its name and semantics. JSON consumers that tolerate unknown keys (most do) won't need to change anything.

Only strict-schema validators (SARIF strict mode, etc.) need the two new keys allow-listed.

## What's next

v1.0 is a starting point. Going through the 1.x line I'm planning to extend the callee / AI-context enrichment surface, expose passive-scan rule categories more directly, and explore SAST-lite territory beyond secret detection. All without breaking v0 compat.

Full change list: [CHANGELOG v1.0.0](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100).

Upgrades use the same paths as always:

```bash
brew upgrade noir
# or
docker pull ghcr.io/owasp-noir/noir:1.0.0
# or
gh release download v1.0.0 -R owasp-noir/noir
```

Feedback and regression reports welcome on [GitHub Issues](https://github.com/owasp-noir/noir/issues). Happy hunting.
