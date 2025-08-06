+++
title = "Ollama"
description = "Instructions for integrating Noir with Ollama for local LLM-powered endpoint analysis"
weight = 2
sort_by = "weight"

[extra]
+++

## Setup Ollama

1. Install Ollama: Follow the instructions on the [official Ollama website](https://ollama.com) to install the required software.
2. Run the Model: Ensure the desired model is available and running.

### Example Command to Serve the Model

To serve the VLLM model "microsoft/phi-4", use the following command:

```bash
ollama pull "phi4"
ollama serve "phi4"
```

## Run Noir with Ollama

To leverage Ollama capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=phi4
```

This command performs the standard Noir operations while utilizing the specified Ollama model for enhanced analysis.
