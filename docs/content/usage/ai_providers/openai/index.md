+++
title = "Using Noir with OpenAI"
description = "Connect Noir with OpenAI models like GPT-4o for AI-powered code analysis."
weight = 4
sort_by = "weight"

+++

Integrate Noir with [OpenAI](https://openai.com) to leverage language models like GPT-4o for advanced code analysis and endpoint detection.

## Setup

1.  **Get an API Key**: Generate from [OpenAI dashboard](https://platform.openai.com/api-keys)
2.  **Choose a Model**: Recommended: `gpt-4o`

## Usage

Run Noir with OpenAI:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-4o \
     --ai-key=sk-...
```

OpenAI enables natural language endpoint descriptions, security vulnerability identification, and code quality suggestions.

