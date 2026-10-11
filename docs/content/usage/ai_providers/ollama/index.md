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

3.  **Start the Server**:

    ```bash
    ollama serve
    ```

## Usage

Run Noir with Ollama:

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=gemma4
```

## Notes

- The `ollama` preset talks to Ollama's native `/api/generate` API, not the OpenAI-compatible `/v1` mount. Noir sets `num_ctx` to the prompt budget it sized its requests for, so long prompts are not cut to Ollama's small default context.
- A hosted Ollama or an authenticating proxy can take a bearer token from `--ai-key` or `NOIR_AI_KEY`.
- `--ai-stream` does not apply to this provider.

> **v0 → v1 migration:** The standalone `--ollama` / `--ollama-model`
> flags were removed in v1.0. Use the unified `--ai-provider ollama
> --ai-model NAME` form (shown above).

