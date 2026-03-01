+++
title = "Using Noir with Azure AI"
description = "Connect Noir with Azure AI language models for code analysis."
weight = 2
sort_by = "weight"

+++

Use [Azure AI](https://azure.microsoft.com/en-us/products/ai-services) language models through GitHub Models inference endpoint.

## Setup

1.  **API Key**: Get from [Azure AI Inference portal](https://models.inference.ai.azure.com)
2.  **Model**: Select available Azure AI model

## Usage

Run Noir with Azure AI:

```bash
noir -b ./myapp \
     --ai-provider=azure \
     --ai-model=YOUR_MODEL_NAME \
     --ai-key=YOUR_API_KEY
```

The `azure` provider uses endpoint: `https://models.inference.ai.azure.com`

Using environment variable:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir -b ./myapp --ai-provider=azure --ai-model=YOUR_MODEL_NAME
```

Azure AI enables natural language endpoint descriptions, security vulnerability identification, and code quality suggestions.
