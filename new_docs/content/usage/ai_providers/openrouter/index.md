+++
title = "Using Noir with OpenRouter"
description = "Learn how to use OpenRouter with Noir to access multiple AI models through a unified API. This guide covers how to set up your OpenRouter API key and run Noir with various models."
weight = 7
sort_by = "weight"

+++

Use [OpenRouter](https://openrouter.ai) to access multiple AI models (OpenAI, Anthropic, Google, Meta, etc.) through a single unified API.

## Setup

1.  **API Key**: Get from [OpenRouter dashboard](https://openrouter.ai/keys)
2.  **Model**: Browse available models at [OpenRouter Models](https://openrouter.ai/models)

## Usage

Run Noir with OpenRouter:

```bash
noir -b ./myapp \
     --ai-provider=openrouter \
     --ai-model=anthropic/claude-3.5-sonnet \
     --ai-key=sk-or-...
```

Using environment variable:

```bash
export NOIR_AI_KEY=sk-or-...
noir -b ./myapp --ai-provider=openrouter --ai-model=openai/gpt-4o
```

OpenRouter provides:
*   Access to 100+ models from multiple providers
*   Unified API for all models
*   Automatic fallbacks and load balancing
*   Cost-effective model selection

