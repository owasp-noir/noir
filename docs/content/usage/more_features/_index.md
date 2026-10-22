+++
title = "Additional Features"
description = "Tagger adds contextual tags; Diff Mode compares attack surfaces across revisions; Deliver pushes results to other tools (Burp Suite, ZAP, Elasticsearch, etc.)."
weight = 10
sort_by = "weight"

+++

Besides finding endpoints, Noir can tag them, compare them across versions, and send them to other tools:

*   **Tagger**: attaches contextual tags to endpoints and parameters (e.g. `oauth`, `websocket`, `pii`, and per-parameter hints like `sqli` or `idor`). Tags help a reviewer, human or LLM, pick what to read first.
*   **Diff Mode**: compares the attack surface of the working tree against another path or a git revision (`--diff-ref`), reports added/removed/changed endpoints and lost auth, and can fail CI with `--fail-on`. See [Comparing Code with Diff Mode](@/usage/more_features/diff/index.md).
*   **Deliver**: sends results to Burp Suite, ZAP, Elasticsearch, or a webhook, so Noir fits into the pipeline you already run.
