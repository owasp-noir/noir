+++
title = "Using Noir with OpenAI"
description = "This guide shows you how to connect Noir with OpenAI's powerful language models, like GPT-4o, to get advanced analysis of your code. Learn how to configure your API key and run Noir with OpenAI."
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

OpenAI provides:
*   Natural language descriptions of endpoints
*   Identification of potential security vulnerabilities
*   Code quality improvement suggestions

