+++
title = "Using Noir with LM Studio"
description = "Learn how to integrate Noir with LM Studio to run local language models for code analysis. This guide shows you how to set up the LM Studio server and connect it to Noir."
weight = 3
sort_by = "weight"

[extra]
+++

[LM Studio](https://lmstudio.ai) is a popular application that makes it easy to download and run large language models (LLMs) on your local machine. By integrating Noir with LM Studio, you can get the benefits of AI-powered code analysis without sending your code to a third-party service.

## Setting Up LM Studio

To use LM Studio with Noir, you first need to download the application and start the local inference server.

1.  **Install LM Studio**: Download and install LM Studio from the [official website](https://lmstudio.ai).
2.  **Start the Local Server**: Open LM Studio, select a model, and then navigate to the "Local Server" tab. Click "Start Server" to make the model available via a local API endpoint.

    ![](./lmstudio.png)

## Running Noir with LM Studio

Once the LM Studio server is running, you can connect Noir to it by using the `lmstudio` AI provider.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=lmstudio \
     --ai-model <MODEL_NAME>
```

Replace `<MODEL_NAME>` with the name of the model you are serving in LM Studio. Noir will then send the discovered endpoints to the local server for analysis.

This setup provides a powerful and private way to leverage AI for code analysis, giving you complete control over your data.

