+++
title = "GitHub Models Provider (Retired)"
description = "GitHub Models was retired on July 30, 2026. Read the migration note and choose a supported Noir AI provider."
weight = 6
sort_by = "weight"

+++

GitHub retired [GitHub Models](https://docs.github.com/en/github-models) on July 30, 2026. Its model catalog, inference API, playground, and bring-your-own-key flow are no longer available.

This page remains as a migration note for older Noir configurations. Do not use the `github` provider for new scans.

## Choose a supported provider

Use one of Noir's supported providers instead:

*   [Azure AI](../azure/): connect to a Microsoft Foundry resource.
*   [OpenAI](../openai/): use OpenAI models through the OpenAI API.
*   [OpenRouter](../openrouter/): access multiple models through one API.
*   [ACP agents](../acp/): connect Noir to Codex, Gemini, Claude, or another ACP-compatible agent.

{% alert_warning() %}
The `github` provider is retained in Noir for compatibility with older configurations, but GitHub Models itself is no longer a working service. Use a supported provider from the list above.
{% end %}
