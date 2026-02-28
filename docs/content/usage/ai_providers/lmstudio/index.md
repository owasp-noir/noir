+++
title = "Using Noir with LM Studio"
description = "Learn how to integrate Noir with LM Studio to run local language models for code analysis. This guide shows you how to set up the LM Studio server and connect it to Noir."
weight = 3
sort_by = "weight"

+++

Run local language models using [LM Studio](https://lmstudio.ai) for private code analysis.

## Setup

1.  **Install**: Download from [lmstudio.ai](https://lmstudio.ai)
2.  **Start Server**: Open LM Studio, select a model, navigate to "Local Server" tab, and click "Start Server"

    ![](./lmstudio.png)

## Usage

Run Noir with LM Studio:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=lmstudio \
     --ai-model <MODEL_NAME>
```

Replace `<MODEL_NAME>` with your LM Studio model name.

