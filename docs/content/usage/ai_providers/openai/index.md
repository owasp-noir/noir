+++
title = "Using Noir with OpenAI"
description = "Connect Noir with OpenAI models like GPT-5.5 for AI-powered code analysis."
weight = 4
sort_by = "weight"

+++

Connect Noir to [OpenAI](https://openai.com) and use models like GPT-5.5 for LLM-based code analysis and endpoint detection.

## Setup

1.  **Get an API Key**: Create one in the [OpenAI dashboard](https://platform.openai.com/api-keys)
2.  **Choose a Model**: `gpt-5.5` is recommended

## Usage

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-5.5 \
     --ai-key=sk-...
```

