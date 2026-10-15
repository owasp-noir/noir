+++
title = "Using Noir with vLLM"
description = "Integrate Noir with vLLM for high-performance local LLM inference."
weight = 3
sort_by = "weight"

+++

Serve a model locally with [vLLM](https://docs.vllm.ai) and point Noir at it.

## Setup

1.  **Install vLLM**: Follow the [official installation guide](https://docs.vllm.ai).
2.  **Serve a Model**:

    ```bash
    vllm serve google/gemma-4-31B-it
    ```

    This starts an OpenAI-compatible server on port 8000.

## Usage

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=google/gemma-4-31B-it
```

The `vllm` preset points at `http://localhost:8000/v1`. For another host or port, pass the URL instead, for example `--ai-provider=http://gpu-box:8000/v1`.
