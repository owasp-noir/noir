---
title: OpenAI
parent: AI Integration
nav_order: 4
layout: page
---

## Setup OpenAI

1. Obtain an API Key: Follow the instructions on the [official OpenAI website](https://openai.com/api/) to obtain an API key.
2. Configure the Model: Ensure the desired model is available and configured.

## Run Noir with OpenAI

To leverage OpenAI capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-4o \
     --ai-key=sk-svca....
```

This command performs the standard Noir operations while utilizing the specified OpenAI model for enhanced analysis.
