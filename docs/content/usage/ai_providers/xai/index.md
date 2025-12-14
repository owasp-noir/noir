+++
title = "Using Noir with xAI"
description = "Learn how to integrate Noir with xAI's Grok models for advanced code analysis. This guide covers how to set up your xAI API key and run Noir to get deep insights into your endpoints."
weight = 5
sort_by = "weight"

[extra]
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

xAI provides:
*   Complex endpoint analysis
*   Security vulnerability identification
*   Code improvement suggestions

