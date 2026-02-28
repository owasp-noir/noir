+++
title = "Using Noir with Ollama"
description = "Learn how to integrate Noir with Ollama to run local large language models (LLMs) for in-depth endpoint analysis. This guide provides setup instructions and example commands."
weight = 2
sort_by = "weight"

+++

Run large language models locally using [Ollama](https://ollama.com) for code analysis without sending data to external services.

## Setup

1.  **Install Ollama**: Download from [ollama.com](https://ollama.com)
2.  **Download a Model**: Pull a model (e.g., `phi-3`)

    ```bash
    ollama pull phi-3
    ```

3.  **Serve the Model**:

    ```bash
    ollama serve phi-3
    ```

## Usage

Run Noir with Ollama:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=phi-3
```

Ollama provides local AI analysis for vulnerability detection, code improvements, and endpoint functionality descriptions.

