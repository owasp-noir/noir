+++
title = "Using Noir with ACP Agents"
description = "Use ACP-based agents such as Codex, Gemini, and Claude with Noir for AI-powered endpoint analysis."
weight = 8
sort_by = "weight"

+++

Use ACP (Agent Client Protocol) providers when you want Noir to talk to an AI agent process instead of a direct HTTP LLM API.

## Supported ACP Providers

- `acp:codex` -> runs `npx @zed-industries/codex-acp`
- `acp:gemini` -> runs `gemini --experimental-acp`
- `acp:claude` -> runs `npx @zed-industries/claude-agent-acp`
- `acp:<custom>` -> runs `<custom>` as an ACP-compatible command

## Usage

### Codex (recommended test target)

```bash
noir -b ./myapp --ai-provider=acp:codex
```

### Gemini

```bash
noir -b ./myapp --ai-provider=acp:gemini
```

### Claude

```bash
noir -b ./myapp --ai-provider=acp:claude
```

### Optional model

For `acp:*`, `--ai-model` is optional.

```bash
noir -b ./myapp --ai-provider=acp:codex --ai-model=codex
```

## Logging Behavior

By default, Noir wraps ACP lifecycle events in Noir-style logs and suppresses raw ACP/agent stderr noise.

Set this if you need raw ACP and agent logs:

```bash
NOIR_ACP_RAW_LOG=1 noir -b ./myapp --ai-provider=acp:codex
```

## Notes

- `--ai-key` is not required for `acp:*` providers.
- Cache flags (`--cache-disable`, `--cache-clear`) work the same as other AI providers.
- `acp:claude-code` is accepted as an alias of `acp:claude`.
