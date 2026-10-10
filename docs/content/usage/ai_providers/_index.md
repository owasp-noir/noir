+++
title = "AI Providers"
description = "Learn how to connect Noir to supported AI providers such as OpenAI, Azure AI, OpenRouter, and local or ACP runtimes."
weight = 3
sort_by = "weight"

+++

Noir's LLM analysis supports cloud APIs, local runtimes for offline or private use, and ACP agents. Legacy integrations are listed separately so existing configurations remain discoverable.

## Provider Comparison

| Provider | Type | API Key | Internet | Best For |
|---|---|---|---|---|
| [OpenAI](openai/) | Cloud | Required | Required | High accuracy, latest models |
| [xAI](xai/) | Cloud | Required | Required | Grok models |
| [Azure AI](azure/) | Cloud | Required | Required | Enterprise, compliance |
| [Anthropic](anthropic/) | Cloud | Required | Required | Claude models, native API |
| [Google Gemini](gemini/) | Cloud | Required | Required | Gemini models |
| [OpenRouter](openrouter/) | Cloud | Required | Required | Access to multiple models via one API |
| [Ollama](ollama/) | Local | Not needed | Not needed | Privacy, offline, free |
| [vLLM](vllm/) | Local | Not needed | Not needed | High-performance local inference |
| [LM Studio](lmstudio/) | Local | Not needed | Not needed | GUI-based local models |
| [ACP](acp/) | Agent | Varies | Varies | Agent-based workflows (Codex, Gemini, Claude) |

## Detailed Guides

*   **Cloud-Based Providers**:
    *   [OpenAI](openai/)
    *   [xAI](xai/)
    *   [Azure AI](azure/)
    *   [Anthropic](anthropic/)
    *   [Google Gemini](gemini/)
    *   [OpenRouter](openrouter/)
*   **Local Model Providers**:
    *   [Ollama](ollama/)
    *   [vLLM](vllm/)
    *   [LM Studio](lmstudio/)
*   **ACP Agent Providers**:
    *   [ACP (Codex/Gemini/Claude/Custom)](acp/)

## Retired integrations

*   **[GitHub Models provider (retired)](github_marketplace/)**: GitHub retired GitHub Models on July 30, 2026. The page is kept as a migration note for older Noir configurations.
