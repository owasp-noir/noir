+++
title = "AI Providers"
description = "Learn how to connect Noir to supported AI providers such as OpenAI, Azure AI, OpenRouter, and local or ACP runtimes."
weight = 3
sort_by = "weight"

+++

Noir's AI analysis can use cloud APIs, local model servers, or ACP agents.

`--ai-provider` takes a preset name from the table below or any OpenAI-compatible URL (for example `http://localhost:8000/v1`). Pass the API key with `NOIR_AI_KEY` or `--ai-key-file`; `--ai-key` works too, but the key is then visible in the process list.

## Providers

| Provider | Type | API Key | Internet | Notes |
|---|---|---|---|---|
| [OpenAI](openai/) | Cloud | Required | Required | GPT models |
| [xAI](xai/) | Cloud | Required | Required | Grok models |
| [Azure AI](azure/) | Cloud | Required | Required | Use your Foundry resource URL |
| [Anthropic](anthropic/) | Cloud | Required | Required | Claude models, native Messages API |
| [Google Gemini](gemini/) | Cloud | Required | Required | Gemini models |
| [OpenRouter](openrouter/) | Cloud | Required | Required | Many vendors' models behind one key |
| [Ollama](ollama/) | Local | Not needed | Not needed | Native Ollama API |
| [vLLM](vllm/) | Local | Not needed | Not needed | OpenAI-compatible server |
| [LM Studio](lmstudio/) | Local | Not needed | Not needed | Desktop app with a local server |
| [ACP](acp/) | Agent | Not needed | Required | Codex, Gemini or Claude agent, signed in on its own |

## Retired integrations

*   [GitHub Models provider (retired)](github_marketplace/): GitHub retired GitHub Models on July 30, 2026. The page is kept as a migration note for older Noir configurations.
