+++
title = "Using Noir with Ollama"
description = "Learn how to integrate Noir with Ollama to run local large language models (LLMs) for in-depth endpoint analysis. This guide provides setup instructions and example commands."
weight = 2
sort_by = "weight"

[extra]
+++

[Ollama](https://ollama.com) is a powerful tool that allows you to run large language models (LLMs) locally on your own machine. By integrating Noir with Ollama, you can leverage the analytical capabilities of these models to gain deeper insights into your code without sending any data to external services.

This setup is ideal for security-conscious environments or for developers who want to experiment with different open-source models for code analysis.

## Setting Up Ollama

Before you can use Ollama with Noir, you need to have it installed and running with a model.

1.  **Install Ollama**: If you haven't already, download and install Ollama from the [official website](https://ollama.com).
2.  **Download a Model**: You'll need to pull a model to use for analysis. In this example, we'll use `phi-3`, a powerful and lightweight model from Microsoft.

    ```bash
    ollama pull phi-3
    ```

3.  **Serve the Model**: To make the model available for Noir, you need to serve it. This is typically handled automatically by Ollama when you run a command, but you can ensure it's running with:

    ```bash
    ollama serve phi-3
    ```

## Running Noir with Ollama

Once Ollama is set up and the model is served, you can run Noir with the `--ai-provider` flag set to `ollama`. You also need to specify which model to use with the `--ai-model` flag.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=phi-3
```

When you run this command, Noir will perform its standard analysis and then send the discovered endpoints to the local Ollama-served model for further inspection. The model can identify potential security vulnerabilities, suggest improvements, or provide a natural language summary of the endpoint's functionality.

This integration allows you to combine Noir's powerful code-scanning capabilities with the advanced reasoning of local LLMs, giving you a comprehensive and secure way to analyze your applications.

