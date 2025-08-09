+++
title = "Using Noir with xAI"
description = "Learn how to integrate Noir with xAI's Grok models for advanced code analysis. This guide covers how to set up your xAI API key and run Noir to get deep insights into your endpoints."
weight = 5
sort_by = "weight"

[extra]
+++

By connecting Noir with [xAI](https://x.ai), you can leverage the advanced reasoning capabilities of models like Grok to perform in-depth analysis of your codebase. This integration allows you to go beyond simple endpoint discovery and gain a deeper understanding of your application's functionality and potential security posture.

## Setting Up the xAI Integration

To get started, you'll need an API key from xAI.

1.  **Obtain an API Key**: Visit the [official xAI website](https://x.ai/api) and follow the instructions to get your API key.
2.  **Choose a Model**: Select the xAI model you want to use for analysis. In this example, we'll use `grok-2-1212`, but you can choose any available model.

## Running Noir with xAI

Once you have your API key, you can run Noir with the `--ai-provider` flag set to `xai`. You will also need to provide your API key with the `--ai-key` flag and specify the model you wish to use with `--ai-model`.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=xai \
     --ai-model=grok-2-1212 \
     --ai-key=xai-...
```

When you run this command, Noir will first scan your code to identify all the endpoints. It will then pass this information to the xAI API, which will analyze the code and return detailed insights. This can help you:

*   Understand the purpose of complex endpoints.
*   Identify potential security vulnerabilities.
*   Get suggestions for improving your code.

This powerful combination brings the cutting-edge capabilities of xAI's models directly into your development workflow, helping you build more secure and robust applications.

