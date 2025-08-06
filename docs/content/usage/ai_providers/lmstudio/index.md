+++
title = "LM Studio"
description = "Guide to using LM Studio with Noir for local LLM-powered endpoint detection and analysis"
weight = 3
sort_by = "weight"

[extra]
+++

## Setup LMStudio

1. Install LMStudio: Follow the instructions on the [official LMStudio website](https://lmstudio.ai) to install the required software.
2. Run the Model: Ensure the desired model is available and running.

### Serve the Model

![](./lmstudio.png)

## Run Noir with LMStudio

To leverage LMStudio capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=lmstudio \
     --ai-model=phi-4
```

This command performs the standard Noir operations while utilizing the specified LMStudio model for enhanced analysis.
