+++
title = "xAI"
description = "Instructions for setting up and using xAI's Grok models with Noir for advanced endpoint detection"
weight = 5
sort_by = "weight"

[extra]
+++

## Setup xAI

1. Obtain an API Key: Follow the instructions on the [official xAI website](https://x.ai/api) to obtain an API key.
2. Configure the Model: Ensure the desired model is available and configured.

## Run Noir with xAI

To leverage xAI capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=xai \
     --ai-model=grok-2-1212 \
     --ai-key=xai-t
```

This command performs the standard Noir operations while utilizing the specified xAI model for enhanced analysis.
