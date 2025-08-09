+++
title = "Using Noir with vLLM"
description = "This guide explains how to integrate Noir with vLLM for high-performance local LLM inference. Learn how to set up vLLM and use it with Noir to accelerate your code analysis."
weight = 3
sort_by = "weight"

[extra]
+++

[vLLM](https://docs.vllm.ai) is a high-throughput and memory-efficient inference engine for large language models (LLMs). By using vLLM with Noir, you can significantly speed up the analysis of your codebase, especially when working with large or complex models. This integration is perfect for developers who need fast, local, and private code analysis.

## Setting Up vLLM

To get started, you'll need to install vLLM and serve a model.

1.  **Install vLLM**: Follow the installation instructions on the [official vLLM website](https://docs.vllm.ai) to set up the required software.
2.  **Serve a Model**: Once vLLM is installed, you can serve any compatible model. In this example, we'll use Microsoft's `phi-3` model.

    ```bash
    vllm serve microsoft/phi-3
    ```

    This command will start a local server that provides an OpenAI-compatible API endpoint for the model.

## Running Noir with vLLM

With your model being served by vLLM, you can now run Noir and point it to your local LLM. Use the `--ai-provider` flag with `vllm` and specify the model you are serving with the `--ai-model` flag.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=microsoft/phi-3
```

When you execute this command, Noir will perform its initial code scan and then send the discovered endpoints to the vLLM-powered API. Because vLLM is highly optimized for performance, you can expect the AI-driven analysis to be much faster than with other local inference solutions.

This powerful combination allows you to build a fast, private, and efficient code analysis pipeline right on your own machine.

