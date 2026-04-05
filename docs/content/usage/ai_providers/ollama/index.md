+++
title = "Using Noir with Ollama"
description = "Integrate Noir with Ollama for local LLM-powered code analysis."
weight = 2
sort_by = "weight"

+++

Run large language models locally using [Ollama](https://ollama.com) for code analysis without sending data to external services.

## Setup

1.  **Install Ollama**: Download from [ollama.com](https://ollama.com)
2.  **Download a Model**: Pull a model (e.g., `gemma4`)

    ```bash
    ollama pull gemma4
    ```

3.  **Serve the Model**:

    ```bash
    ollama serve gemma4
    ```

## Usage

Run Noir with Ollama:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=gemma4
```

Ollama provides local AI analysis for vulnerability detection, code improvements, and endpoint functionality descriptions.

