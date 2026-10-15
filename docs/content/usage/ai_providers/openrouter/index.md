+++
title = "Using Noir with OpenRouter"
description = "Use OpenRouter with Noir to access multiple AI models through a unified API."
weight = 7
sort_by = "weight"

+++

Use [OpenRouter](https://openrouter.ai) to access multiple AI models (OpenAI, Anthropic, Google, Meta, etc.) through one API.

## Setup

1.  **API Key**: Get from [OpenRouter dashboard](https://openrouter.ai/keys)
2.  **Model**: Browse available models at [OpenRouter Models](https://openrouter.ai/models)

## Usage

```bash
noir scan ./myapp \
     --ai-provider=openrouter \
     --ai-model=anthropic/claude-opus-4-8 \
     --ai-key=sk-or-...
```

Using an environment variable:

```bash
export NOIR_AI_KEY=sk-or-...
noir scan ./myapp --ai-provider=openrouter --ai-model=openai/gpt-5.5
```

