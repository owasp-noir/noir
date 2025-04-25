---
title: AI-powered Analysis
weight: 5
layout: page
---

Noir can leverage LLM services or local LLMs to perform additional analysis.

## Overview Flags

### AI Flags

* `--ai-provider PREFIX|URL`: Specify the AI (LLM) provider or custom API URL. Required for AI features.
* `--ai-model MODEL`: Set the model name to use for AI analysis. Required for AI features.
* `--ai-key KEY`: Provide the API key for authenticating with the AI provider's API. Alternatively, use the `NOIR_AI_KEY` environment variable.

#### Prefixes and Default Hosts

| Prefix  | Default Host                          |
|---------|--------------------------------------|
| openai  | https://api.openai.com               |
| xAI     | https://api.x.ai                     |
| github  | https://models.github.ai             |
| azure   | https://models.inference.ai.azure.com|
| vllm    | http://localhost:8000                |
| ollama  | http://localhost:11434               |
| lmstudio| http://localhost:1234                |

*Custom URL example:* `--ai-provider=http://my-custom-api:9000`

### Ollama Flags
{: .d-inline-block }

Since (v0.19.0) / Deprecated
{: .label .label-yellow }

> **Note:** The Ollama flags are deprecated and will be removed in a future version. Please transition to using the `--ai-provider` and `--ai-model` flags.

* `--ollama URL`: Set the Ollama server URL. Use `--ai-provider` instead.
* `--ollama-model MODEL`: Specify the model for the Ollama server. Use `--ai-model` instead.

## How to Use AI Integration
### Step 1: Configure AI Provider

1. Choose an AI provider and obtain the necessary API key.
2. If you wish to use Local LLM, please install each application.

### Step 2: Run Noir with AI Analysis

To leverage AI capabilities for additional analysis, use the following command:

```bash
noir -b . --ai-provider=openai --ai-model=gpt-4 --ai-key=your-api-key
```

This command performs the standard Noir operations while utilizing the specified AI model for enhanced analysis.

![](../../images/advanced/ai_integration.jpeg)

## Benefits of AI Integration

* Using an LLM allows Noir to handle frameworks or languages that are beyond its original support scope.
* Additional endpoints that might be missed during a standard Noir scan can be identified.
* Note that there is a possibility of false positives, and the scanning speed may decrease depending on the number of LLM parameters and the performance of the machine hosting the service.

## Notes

* Ensure that the AI provider's service is running and accessible at the specified URL before executing the command.
* Replace `gpt-4` with the name of the desired model as required.
