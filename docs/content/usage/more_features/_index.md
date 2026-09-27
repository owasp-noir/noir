+++
title = "Additional Features"
description = "Tagger adds contextual tags; Diff Mode compares attack surfaces across revisions; Deliver pushes results to other tools (Burp Suite, ZAP, Elasticsearch, etc.)."
weight = 10
sort_by = "weight"

+++

Beyond endpoint extraction, Noir ships features that shape how the inventory is used downstream:

*   **Tagger**: attaches contextual tags to endpoints and parameters (e.g. `oauth`, `websocket`, `pii`, and per-parameter hints like `sqli` or `idor`). Useful when you want a code auditor, whether human or LLM, to focus on the entries worth reviewing first.
*   **Diff Mode**: compares the attack surface of the working tree against another path or a git revision (`--diff-ref`), reports added/removed/changed endpoints and lost auth, and can fail CI with `--fail-on`. See [Comparing Code with Diff Mode](@/usage/more_features/diff/index.md).
*   **Deliver**: pushes findings to Burp Suite, ZAP, Elasticsearch, and similar tools so Noir's output fits into a pipeline you already run.
