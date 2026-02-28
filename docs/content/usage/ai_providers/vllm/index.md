+++
title = "Using Noir with vLLM"
description = "Integrate Noir with vLLM for high-performance local LLM inference."
weight = 3
sort_by = "weight"

+++

Use [vLLM](https://docs.vllm.ai), a high-throughput inference engine for LLMs, to run fast local code analysis with Noir.

## Setup

1.  **Install vLLM**: Follow the [official installation guide](https://docs.vllm.ai).
2.  **Serve a Model**:

    ```bash
    vllm serve microsoft/phi-3
    ```

    This starts a local server with an OpenAI-compatible API endpoint.

## Usage

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=microsoft/phi-3
```
