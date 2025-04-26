---
title: VLLM
parent: AI Integration
nav_order: 3
layout: page
description: "Guide for setting up and using VLLM with Noir for efficient local model inference and endpoint analysis"
---

## Setup VLLM

1. Install VLLM: Follow the instructions on the [official VLLM website](https://docs.vllm.ai) to install the required software.
2. Run the Model: Ensure the desired model is available and running.

### Example Command to Serve the Model

To serve the VLLM model "microsoft/phi-4", use the following command:

```bash
vllm serve "microsoft/phi-4"
```

## Run Noir with VLLM

To leverage VLLM capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=microsoft/phi-4
```

This command performs the standard Noir operations while utilizing the specified VLLM model for enhanced analysis.
