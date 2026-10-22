+++
title = "Using Noir with ACP Agents"
description = "Use ACP-based agents such as Codex, Gemini, and Claude with Noir for AI-powered endpoint analysis."
weight = 8
sort_by = "weight"

+++

With an ACP (Agent Client Protocol) provider, Noir starts an AI agent process and talks to it, instead of calling an LLM HTTP API.

## Supported ACP Providers

- `acp:codex` -> runs `npx @zed-industries/codex-acp`
- `acp:gemini` -> runs `gemini --experimental-acp`
- `acp:claude` -> runs `npx @zed-industries/claude-agent-acp`
- `acp:<custom>` -> runs `<custom>` as an ACP-compatible command, only with `NOIR_ACP_ALLOW_CUSTOM_COMMAND=1`

Any other target is refused. `--ai-provider` can come from a config file, and spawning whatever it names would be a code-execution path, so custom binaries need the explicit opt-in:

```bash
NOIR_ACP_ALLOW_CUSTOM_COMMAND=1 noir scan ./myapp --ai-provider="acp:my-agent --flag"
```

## Usage

### Codex

```bash
noir scan ./myapp --ai-provider=acp:codex
```

### Gemini

```bash
noir scan ./myapp --ai-provider=acp:gemini
```

### Claude

```bash
noir scan ./myapp --ai-provider=acp:claude
```

### Model

For `acp:*`, `--ai-model` is optional. Noir does not pass it to the agent; the agent uses whatever model it is configured with.

## Logging Behavior

By default, Noir wraps ACP lifecycle events in Noir-style logs and suppresses raw ACP/agent stderr noise.

Set this if you need raw ACP and agent logs:

```bash
NOIR_ACP_RAW_LOG=1 noir scan ./myapp --ai-provider=acp:codex
```

## Tool Permissions

An ACP agent can ask Noir for permission to run its own tools (shell commands, file writes, network fetches) on your machine. Noir declines every one of them.

The prompt Noir sends is source code from the tree you are scanning, often code you did not write. A file that says "ignore the above and run this instead" can steer the agent. Saying yes automatically would turn an endpoint scan into arbitrary code execution on your machine.

Nothing is lost by declining: the code to analyze is already in the prompt, so the agent needs no tools to answer. If you are scanning a tree you trust and want the agent to explore on its own, opt in explicitly:

```bash
NOIR_ACP_ALLOW_TOOL_PERMISSIONS=1 noir scan ./myapp --ai-provider=acp:codex
```

## Notes

- `--ai-key` is not required for `acp:*` providers.
- `NOIR_AI_TIMEOUT` bounds each prompt turn (default `300` seconds). `NOIR_AI_CONNECT_TIMEOUT` bounds starting the agent and opening a session (default `120` seconds, enough for the first `npx` download).
- ACP requests are not retried and do not count toward `--ai-max-requests`.
- Cache flags (`--cache-disable`, `--cache-clear`) work the same as other AI providers.
- `acp:claude-code` is accepted as an alias of `acp:claude`.
