+++
title = "Using Noir with Anthropic"
description = "Use Claude models with Noir through Anthropic's native Messages API."
weight = 4
sort_by = "weight"

+++

The `anthropic` preset talks to [Anthropic](https://www.anthropic.com)'s native Messages API (`/v1/messages`), not its OpenAI-compatible layer. The endpoint schema Noir asks for is sent as `output_config.format`, so Claude's reply is constrained to it.

## Setup

1.  **API Key**: Create one in the [Claude Console](https://platform.claude.com/settings/keys).
2.  **Model**: Pick a model ID such as `claude-opus-5-5` or `claude-sonnet-5-5`.

## Usage

```bash
noir scan ./myapp \
     --ai-provider=anthropic \
     --ai-model=claude-opus-5-5 \
     --ai-key=sk-ant-...
```

Without `--ai-key`, Noir reads `NOIR_AI_KEY`, then `ANTHROPIC_API_KEY`:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
noir scan ./myapp --ai-provider=anthropic --ai-model=claude-sonnet-5-5
```

## Notes

- A gateway in front of the Messages API works too: `--ai-provider=https://gw.example/anthropic/v1/messages`. Any `api.anthropic.com` URL uses the native API unless it ends in `/chat/completions`.
- If a model or gateway rejects the structured-output request, Noir drops it for the rest of the run and relies on the prompt's JSON instructions.
- Models with fixed sampling (Claude Opus 4.7 and later) are sent no `temperature`.
- Each reply is capped at 16,000 output tokens. A reply cut at that cap is reported as truncated, and the complete endpoints before the cut are kept.
- `--ai-agent` uses Claude's native tool calling (`anthropic` is in the default `--ai-native-tools-allowlist`).
