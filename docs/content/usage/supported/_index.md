+++
title = "Supported Technologies"
description = "The technologies Noir supports: programming languages, frameworks, and API specifications."
weight = 1
sort_by = "weight"

+++

What Noir can analyze:

*   **[Languages and Frameworks](language_and_frameworks/)**: The programming languages and web frameworks Noir extracts endpoints and parameters from.
*   **[Specifications](specification/)**: API and data specification formats Noir can parse, such as OpenAPI (Swagger), RAML, and HAR.
*   **[Callee Coverage](callee_coverage/)**: Frameworks that emit best-effort 1-hop handler callees for AI SAST and code review.
*   **[AI Context](ai_context_coverage/)**: Per-endpoint guards, sinks, validators, and signals, aggregated into an AI-review-ready context object with `--ai-context`.
*   **[Mobile Apps](mobile/)**: How Noir extracts Android and iOS deep-link entry points (custom schemes, intents, universal links) and links them to the handling code.
*   **[CLI Apps](cli/)**: How Noir maps the command-line attack surface (subcommands, flags, positional arguments, consumed environment variables) across 21 languages.
