+++
title = "Using Noir with LM Studio"
description = "Integrate Noir with LM Studio for local, private code analysis."
weight = 3
sort_by = "weight"

+++

Run local language models using [LM Studio](https://lmstudio.ai) for private code analysis.

## Setup

1.  **Install**: Download from [lmstudio.ai](https://lmstudio.ai)
2.  **Start the server**: Open LM Studio, go to the Developer tab, load a model, and switch the server status to Running.

    ![The LM Studio Developer tab with status Running and the phi-4 model loaded and ready to serve requests.](./lmstudio.png)

## Usage

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=lmstudio \
     --ai-model <MODEL_NAME>
```

Replace `<MODEL_NAME>` with the model name LM Studio is serving. The `lmstudio` preset points at `http://localhost:1234/v1`; if you changed the port, pass the URL instead.

