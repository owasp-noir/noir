+++
title = "Using Noir with Azure AI"
description = "This guide shows you how to connect Noir with Azure AI's language models through GitHub Models. Learn how to configure your API key and run Noir with Azure AI."
weight = 2
sort_by = "weight"

[extra]
+++

By integrating Noir with [Azure AI](https://azure.microsoft.com/en-us/products/ai-services), you can leverage powerful language models hosted on Microsoft's Azure platform. Azure AI provides access to various models through the GitHub Models inference endpoint, making it easy to get AI-powered analysis of your codebase.

## Setting Up the Azure AI Integration

To use Noir with Azure AI, you'll need access to Azure AI services through GitHub Models.

1.  **Get an API Key**: Sign up for Azure AI services and obtain an API key from the [Azure AI Inference portal](https://models.inference.ai.azure.com).
2.  **Choose a Model**: Select an appropriate model available through Azure AI. Models vary in capability and pricing.

## Running Noir with Azure AI

Once you have your API key, you can run Noir with the `--ai-provider` flag set to `azure`. You'll also need to provide your API key using the `--ai-key` flag and specify the model with `--ai-model`.

```bash
noir -b ./myapp \
     --ai-provider=azure \
     --ai-model=YOUR_MODEL_NAME \
     --ai-key=YOUR_API_KEY
```

The `azure` provider prefix automatically uses the Azure AI inference endpoint at `https://models.inference.ai.azure.com`.

## Using Environment Variables

To avoid passing your API key on the command line, you can set it as an environment variable:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir -b ./myapp --ai-provider=azure --ai-model=YOUR_MODEL_NAME
```

When you run this command, Noir will first scan your code to identify endpoints. Then, it will send this information to the Azure AI API for advanced analysis. This can include:

*   **Natural language descriptions** of what each endpoint does.
*   **Identification of potential security vulnerabilities**.
*   **Suggestions for improving code quality** and adherence to best practices.

This integration provides a powerful way to enhance your development workflow with enterprise-grade AI analysis.
