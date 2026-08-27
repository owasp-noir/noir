+++
title = "Using Noir with Azure AI"
description = "Connect Noir with Azure AI language models for code analysis."
weight = 2
sort_by = "weight"

+++

Use [Microsoft Foundry](https://azure.microsoft.com/en-us/products/ai-foundry) (formerly Azure AI Foundry) language models for code analysis.

## Setup

1.  **API Key**: Create a resource and key in the [Microsoft Foundry portal](https://ai.azure.com)
2.  **Model**: Deploy a model and note its deployment name

## Usage

Point `--ai-provider` at your Foundry resource's endpoint:

```bash
noir scan ./myapp \
     --ai-provider=https://YOUR-RESOURCE.services.ai.azure.com/models \
     --ai-model=YOUR_DEPLOYMENT_NAME \
     --ai-key=YOUR_API_KEY
```

`--ai-provider` accepts any OpenAI-compatible URL, so no prefix is needed.

Using an environment variable for the key:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir scan ./myapp \
     --ai-provider=https://YOUR-RESOURCE.services.ai.azure.com/models \
     --ai-model=YOUR_DEPLOYMENT_NAME
```

## The `azure` prefix

Noir ships an `azure` provider prefix that expands to `https://models.inference.ai.azure.com`.

{% alert_warning() %}
That shared endpoint has been retired: `models.inference.ai.azure.com` no longer resolves in DNS, so the bare `--ai-provider=azure` form cannot reach it. Foundry now gives each resource its own endpoint. Use the full URL shown above instead.
{% end %}
