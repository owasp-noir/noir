+++
title = "Using Noir with OpenAI"
description = "This guide shows you how to connect Noir with OpenAI's powerful language models, like GPT-4o, to get advanced analysis of your code. Learn how to configure your API key and run Noir with OpenAI."
weight = 4
sort_by = "weight"

[extra]
+++

By integrating Noir with [OpenAI](https://openai.com), you can harness the power of state-of-the-art language models like GPT-4o to analyze your codebase. This combination allows you to go beyond simple endpoint detection and get sophisticated insights into your application's behavior, potential security risks, and overall quality.

## Setting Up the OpenAI Integration

To use Noir with OpenAI, you'll need an API key.

1.  **Get an API Key**: If you don't already have one, sign up for an OpenAI account and generate an API key from your [dashboard](https://platform.openai.com/api-keys).
2.  **Choose a Model**: Decide which OpenAI model you want to use. For the best results, we recommend a powerful and up-to-date model like `gpt-4o`.

## Running Noir with OpenAI

Once you have your API key, you can run Noir with the `--ai-provider` flag set to `openai`. You'll also need to provide your API key using the `--ai-key` flag and specify the model with `--ai-model`.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-4o \
     --ai-key=sk-...
```

When you run this command, Noir will first scan your code to identify endpoints. Then, it will send this information to the OpenAI API, which will analyze the code and provide additional insights. This can include:

*   **Natural language descriptions** of what each endpoint does.
*   **Identification of potential security vulnerabilities**.
*   **Suggestions for improving code quality** and adherence to best practices.

This integration is a powerful way to augment your development workflow, giving you access to world-class AI analysis without leaving your command line.

