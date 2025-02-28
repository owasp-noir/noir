---
title: X.AI
parent: AI Integration
nav_order: 5
layout: page
---

# X.AI Integration

## Setup X.AI

1. Obtain an API Key: Follow the instructions on the [official X.AI website](https://x.ai/api) to obtain an API key.
2. Configure the Model: Ensure the desired model is available and configured.

## Run Noir with X.AI

To leverage X.AI capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=x.ai \
     --ai-model=grok-2-1212 \
     --ai-key=xai-t
```

This command performs the standard Noir operations while utilizing the specified X.AI model for enhanced analysis.
