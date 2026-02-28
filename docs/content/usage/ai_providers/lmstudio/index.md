+++
title = "Using Noir with LM Studio"
description = "Integrate Noir with LM Studio for local, private code analysis."
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

