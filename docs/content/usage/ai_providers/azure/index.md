+++
title = "Using Noir with Azure AI"
description = "This guide shows you how to connect Noir with Azure AI's language models through GitHub Models. Learn how to configure your API key and run Noir with Azure AI."
weight = 2
sort_by = "weight"

[extra]
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

Azure AI provides:
*   Natural language endpoint descriptions
*   Security vulnerability identification
*   Code quality improvement suggestions
