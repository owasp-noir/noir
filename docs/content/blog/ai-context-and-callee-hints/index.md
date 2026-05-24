+++
title = "--ai-context and --include-callee — hint and sink for AI code review"
description = "Two v1 flags that ship structured security context to AI source-code analysis instead of raw code."
date = "2026-05-24"
tags = ["v1", "ai-context", "callee", "design"]
authors = ["hahwul"]
template = "blog_post"
+++

Around late 2025, AI's leap forward reshaped how software gets built — and source-code vulnerability analysis has been moving in the same AI-first direction from roughly the same point.

A lot of AI-based source-code analysis tools and approaches follow the same shape: feed code in, ask an LLM, get a report back. To actually work well, the LLM needs to know *what to look at*. Drop the whole codebase on it and you burn tokens while missing the points that matter.

Noir v1 ships two flags that extract that "what to look at" upfront and pack it into the output.

- `--include-callee` — adds a 1-hop callee graph to each endpoint as a `callees` array
- `--ai-context` — includes the same callee data and sorts it into **five security categories** under `ai_context`

## --include-callee — who calls whom

The simpler of the two. Parses each endpoint handler body with tree-sitter and pulls out 1-hop callees as `{name, path, line}`.

```bash
$ noir -b ./flask_app --include callee -f json
```

```json
{
  "url": "/sign",
  "method": "POST",
  "callees": [
    { "name": "get_hash",          "path": "app/utils.py", "line": 3 },
    { "name": "User.query.filter", "path": "app/app.py",   "line": 21 },
    { "name": "User",              "path": "app/app.py",   "line": 24 },
    { "name": "db_session.add",    "path": "app/app.py",   "line": 25 },
    { "name": "db_session.commit", "path": "app/app.py",   "line": 26 }
  ]
}
```

To an LLM this reads as "to review this endpoint, also look at `utils.py:3` and `app.py:21,24,25,26`". Token-efficient too — instead of shipping the entire codebase, you only need the handler plus those few referenced lines.

## --ai-context — same data, sorted into security categories

`--ai-context` takes the same callee information and runs further analysis to bucket it into five categories.

- **guards** — auth middleware / decorators / access-control checks
- **callees** — same as above but enriched with a code snippet and a confidence score
- **sinks** — potential SQL / command-exec / file-I/O / redirect / template-render endpoints
- **validators** — input-validation calls
- **signals** — heuristic flags like `state_change`, `credential_input`, `guard_absence`

Running the same Flask `/sign` POST endpoint with `--ai-context`

```bash
$ noir -b ./flask_app --ai-context -f json
```

```json
{
  "url": "/sign",
  "method": "POST",
  "ai_context": {
    "sinks": [
      {
        "kind": "sql",
        "name": "query",
        "description": "Potential SQL/data-store sink inferred from code or callee name",
        "path": "app/app.py", "line": 21, "confidence": 78,
        "snippet": "20: password = get_hash(request.form['password'], ...) | 21: if User.query.filter(...).first(): | 22: return render_template('error.html')"
      }
    ],
    "signals": [
      { "kind": "state_change",     "name": "POST",          "confidence": 88 },
      { "kind": "credential_input", "name": "form.password", "confidence": 86 },
      { "kind": "guard_absence",    "name": "POST",          "confidence": 28,
        "description": "No auth guard was detected for this state-changing endpoint." }
    ]
  }
}
```

What the LLM gets from this single endpoint

1. There's a `credential_input` — a password arrives via form
2. It's a `state_change` — POST
3. There's a `guard_absence` — no auth decorator detected
4. There's a `sql` sink — `User.query.filter`

Human reviewer or LLM, four signals stacking on one handler land cleanly: **review this first**. A credential-handling endpoint missing auth is priority 1 without further reasoning.

For contrast, here's a case where `--ai-context` did pick up auth (flask_auth fixture)

```json
{
  "url": "/profile",
  "method": "GET",
  "ai_context": {
    "guards": [{
      "kind": "auth_guard",
      "name": "flask-login login_required",
      "description": "Protected by flask-login login_required",
      "confidence": 86,
      "snippet": "12: | 13: @login_required | 14: @app.route('/profile') | 15: def profile():"
    }]
  }
}
```

The `@login_required` decorator landed in `guards`. To an LLM that's a **negative** signal — "this endpoint already has an auth check, focus on other vuln classes instead".

## Hint and sink at the same time

The interesting bit is that these flags work as both hint and sink at once.

- As a **hint** — pre-curated per-endpoint context narrows the LLM's attention. Instead of "review the entire codebase", it's "this handler plus these files".
- As a **sink** (the source-to-sink kind) — the `sinks` bucket lists framework-aware candidates for where data might land. A generic LLM *can* reason that `User.query.filter` is SQL, but it burns tokens doing so every time. Noir pre-labels them so the LLM can skip that reasoning step.

The framework-aware labeling is where the leverage is. The same callee name `query` means different things in different contexts.

- Flask + SQLAlchemy: `User.query.filter` → SQL sink
- Express + MongoDB: `User.find` → NoSQL sink
- A plain LLM either misses the distinction or re-derives it on every pass

Noir identifies the framework in the detector phase, and the augmentor applies that framework's idioms when matching sink / guard patterns. The LLM consumes pre-labeled, framework-aware context instead of raw code.

## Recommended use

For an AI-driven code review pipeline

```bash
# Every category
noir -b ./app --ai-context -f json

# Narrow to the categories you actually want (saves tokens)
noir -b ./app --ai-context=guards,sinks,signals -f json

# Just callees — lightweight hint
noir -b ./app --include callee -f json
```

The full category set is best for the first audit pass. For incremental review or PR-level checks, `guards,sinks,signals` is usually enough.

## What's next

`--ai-context`'s sink and guard patterns are currently regex-based heuristics. We don't do real data-flow tracing — we mark "this looks like a sink" based on callee names and code patterns, and stop there. That's a deliberate trade-off. Precise taint analysis has dedicated tooling, and Noir aims to be the layer that gives that tool (or an LLM) a fast **focus point** to start from.

Going forward, the pattern catalogue will get more framework-aware and new signal kinds will land. Feedback and new pattern proposals are always welcome.
