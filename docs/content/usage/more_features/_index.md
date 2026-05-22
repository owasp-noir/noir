+++
title = "Additional Features"
description = "Tagger adds contextual tags to endpoints; Deliver pushes results to other tools (Burp Suite, ZAP, Elasticsearch, etc.)."
weight = 10
sort_by = "weight"

+++

Beyond endpoint extraction, Noir ships two features that shape how the inventory is used downstream:

*   **Tagger**: attaches contextual tags to endpoints and parameters (e.g. `shadow`, `websocket`, sink hints). Useful when you want a code auditor, whether human or LLM, to focus on the entries worth reviewing first.
*   **Deliver**: pushes findings to Burp Suite, ZAP, Elasticsearch, and similar tools so Noir's output fits into a pipeline you already run.
