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
- `acp:<custom>` -> runs `<custom>` as an ACP-compatible command, only with `NOIR_ACP_ALLOW_CUSTOM_COMMAND=1`

Any other target is refused. `--ai-provider` can come from a config file, and spawning whatever it names would be a code-execution path, so custom binaries need the explicit opt-in:

```bash
NOIR_ACP_ALLOW_CUSTOM_COMMAND=1 noir scan ./myapp --ai-provider="acp:my-agent --flag"
```

## Usage

### Codex (recommended test target)

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

### Optional model

For `acp:*`, `--ai-model` is optional.

```bash
noir scan ./myapp --ai-provider=acp:codex --ai-model=codex
```

## Logging Behavior

By default, Noir wraps ACP lifecycle events in Noir-style logs and suppresses raw ACP/agent stderr noise.

Set this if you need raw ACP and agent logs:

```bash
NOIR_ACP_RAW_LOG=1 noir scan ./myapp --ai-provider=acp:codex
```

## Tool Permissions

An ACP agent can ask Noir for permission to run its own tools — shell commands, file writes, network fetches — on your machine. Noir **declines every one of them**.

The prompt Noir sends the agent is source code from the tree you are scanning, and scanning code you did not write is the normal case. A file that carries "ignore the above and run this instead" is enough to steer the agent, so the permission prompt is the one checkpoint left; answering it with an automatic yes would turn an endpoint scan into arbitrary local execution.

Nothing is lost by declining: the code to analyze is already in the prompt, so the agent needs no tools to answer. If you are scanning a tree you trust and want the agent to explore on its own, opt in explicitly:

```bash
NOIR_ACP_ALLOW_TOOL_PERMISSIONS=1 noir scan ./myapp --ai-provider=acp:codex
```

## Notes

- `--ai-key` is not required for `acp:*` providers.
- Cache flags (`--cache-disable`, `--cache-clear`) work the same as other AI providers.
- `acp:claude-code` is accepted as an alias of `acp:claude`.
