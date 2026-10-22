+++
title = "Using Noir with Google Gemini"
description = "Use Gemini models with Noir through Google's OpenAI-compatible endpoint."
weight = 5
sort_by = "weight"

+++

The `gemini` preset points at Google's [OpenAI-compatible Gemini endpoint](https://ai.google.dev/gemini-api/docs/openai), which accepts the JSON schema Noir sends as `response_format`.

## Setup

1.  **API Key**: Create one in [Google AI Studio](https://aistudio.google.com/apikey).
2.  **Model**: Pick a model ID such as `gemini-3.1-pro` or `gemini-3.5-flash`.

## Usage

```bash
noir scan ./myapp \
     --ai-provider=gemini \
     --ai-model=gemini-3.1-pro \
     --ai-key=AIza...
```

Using an environment variable:

```bash
export NOIR_AI_KEY=AIza...
noir scan ./myapp --ai-provider=gemini --ai-model=gemini-3.5-flash
```
