+++
title = "AI Context"
description = "Per-endpoint AI review context that aggregates guards, callees, sinks, validators, and signals."
weight = 5
sort_by = "weight"

+++

Noir can attach a structured **AI review context** to each endpoint. It groups static signals that LLM-based SAST tools, code reviewers, and security agents commonly need to triage a route, without forcing them to walk the repository themselves.

Use `--ai-context` to enable it:

```bash
noir scan . --ai-context
```

Pass a comma-separated bucket list to narrow the output to just the categories you care about. The filter applies at the data layer, so JSON / SARIF / YAML / Postman / OAS all see the same selection — not just the plain-text renderer.

```bash
noir scan . --ai-context=guards,sinks       # only auth + likely-dangerous sinks
noir scan . --ai-context=callee             # only the 1-hop handler callees
noir scan . --ai-context=all                # explicit form of "everything"
noir scan . --ai-context                    # bare form: also "everything"
```

Valid feature names: `guards`, `callee`, `sinks`, `validators`, `signals` (plus `all`). Names are case-insensitive.

In plain output, every endpoint with non-empty context grows an `ai_context:` block. Model-based formats expose the same structure under standard locations:

| Format | Where AI context appears |
|---|---|
| JSON / JSONL / YAML / TOML | `endpoints[].ai_context` |
| OpenAPI 2.0 / 3.0 | Operation-level `x-noir-ai-context` extension |
| SARIF | `result.properties.noir.ai_context` |
| Postman | Appended to the item description |
| cURL / HTTPie / only-url / only-param | Omitted on purpose (primary output stays stable) |

## What goes inside

Every context bucket is a list of entries with `kind`, `name`, optional `source`, `description`, `path`, `line`, `confidence`, and `snippet`. The buckets are:

| Bucket | Meaning |
|---|---|
| `guards` | Authentication / authorization gates detected on the route (middleware, decorators, `requires_auth`, role checks, etc.) |
| `callees` | The 1-hop handler callees Noir already collects with `--include callee`, re-emitted under the AI context structure for one-stop consumption |
| `sinks` | Likely dangerous operations inferred from the handler body or callee names (SQL, command execution, deserialization, template rendering, file I/O, redirects, etc.) |
| `validators` | Input-validation and sanitization signals (schema validators, parameter coercion, allow-listing patterns) that mitigate sink risk |
| `signals` | Other route-shape hints worth surfacing (state-changing methods without a detected guard, path-id usage suggesting object-level authorization concerns, file-upload behavior, etc.) |

The list is best-effort. Heuristic confidence is exposed on each entry so consumers can filter by threshold. Up to 16 entries per bucket are kept to keep output compact.

## Typical use cases

- **AI SAST**: hand the endpoint inventory plus its AI context to an LLM so it can decide where vulnerabilities are reachable from the attack surface without re-discovering the route structure.
- **Manual triage**: a reviewer skimming a large JSON or SARIF report can sort or filter by sink kind or by `signals` like `state_changing_without_guard`.
- **CI gating**: surface `sinks` minus `validators` to flag risky endpoints in pull requests.

## Combine with other flags

```bash
# Plain output with both 1-hop callees and the full AI context block
noir scan . --include callee --ai-context

# JSON output suitable for LLM-driven SAST pipelines
noir scan . --ai-context -f json -o noir-context.json

# OpenAPI export with `x-noir-ai-context` on every operation
noir scan . --ai-context -f oas3 -o spec.json
```

## Completeness notes

- AI context is **additive**: endpoints unaffected by any heuristic come out exactly as they would without the flag (no `ai_context` key in serialized models).
- Heuristics are tuned conservatively. Both false positives and false negatives exist; treat entries as priors, not findings.
- Guard / sink / validator patterns improve over time. The set is intentionally cross-language so a single context schema works across the framework matrix Noir already covers.
- Callee coverage drives much of the AI context. See [Callee Coverage](@/usage/supported/callee_coverage/index.md) for which frameworks expose handler callees today.
