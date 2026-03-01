+++
title = "Using Noir with xAI"
description = "Integrate Noir with xAI Grok models for code analysis."
weight = 5
sort_by = "weight"

+++

Use [xAI](https://x.ai) Grok models for advanced code analysis and endpoint discovery.

## Setup

1.  **API Key**: Get from [xAI website](https://x.ai/api)
2.  **Model**: Choose model (e.g., `grok-2-1212`)

## Usage

Run Noir with xAI:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=xai \
     --ai-model=grok-2-1212 \
     --ai-key=xai-...
```

xAI enables endpoint analysis, security vulnerability identification, and code improvement suggestions.

