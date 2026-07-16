+++
title = "AI Providers"
description = "Learn how to connect Noir to various AI providers, including OpenAI, xAI, and local/agent-based runtimes like Ollama, LM Studio, and ACP."
weight = 3
sort_by = "weight"

+++

Noir's LLM analysis works with any of the providers below: cloud APIs, local runtimes for offline or private use, and ACP agents.

## Provider Comparison

| Provider | Type | API Key | Internet | Best For |
|---|---|---|---|---|
| [OpenAI](openai/) | Cloud | Required | Required | High accuracy, latest models |
| [xAI](xai/) | Cloud | Required | Required | Grok models |
| [Azure AI](azure/) | Cloud | Required | Required | Enterprise, compliance |
| [GitHub Marketplace](github_marketplace/) | Cloud | GitHub PAT | Required | GitHub ecosystem users |
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
    *   [GitHub Marketplace](github_marketplace/)
    *   [OpenRouter](openrouter/)
*   **Local Model Providers**:
    *   [Ollama](ollama/)
    *   [vLLM](vllm/)
    *   [LM Studio](lmstudio/)
*   **ACP Agent Providers**:
    *   [ACP (Codex/Gemini/Claude/Custom)](acp/)
