+++
title = "Debug with hidden flags"
description = "Developer-only flags not shown in --help for debugging and experimentation"
weight = 3
sort_by = "weight"

+++

These are developer-only flags. They do not appear in the CLI help output, but they are available for advanced experimentation and debugging. Names, behavior, and availability may change without notice.

Available flags

- `--override-analyze-prompt`
  - Overrides the internal ANALYZE_PROMPT used for individual file analysis.
- `--override-llm-optimize-prompt`
  - Overrides the internal LLM_OPTIMIZE_PROMPT used for endpoint optimization.
- `--override-bundle-analyze-prompt`
  - Overrides the internal BUNDLE_ANALYZE_PROMPT used for bundled (multi-file) analysis.
- `--override-filter-prompt`
  - Overrides the internal FILTER_PROMPT used for file filtering.

When to use these flags

- You are developing or testing new prompt strategies for analysis, filtering, or optimization.
- You need to rapidly iterate without rebuilding.
- You want to compare the impact of prompt variations on output quality.

General usage tips

- Quote your prompt strings to preserve spaces and special characters.
- For long, multi-line prompts, read from a file with command substitution.
- Start with a small fixture directory to validate behavior before scaling up.
- Combine with `--verbose` to inspect intermediate steps more easily.

Examples

Short literal prompt (single file analysis override)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-analyze-prompt 'Identify HTTP endpoints and parameters. Return concise structured results.'
```

Read a multi-line prompt from a file (analyze override)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-analyze-prompt "$(cat prompts/analyze_prompt.txt)"
```

Override the LLM optimizer prompt

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-llm-optimize-prompt "$(cat prompts/llm_optimize_prompt.txt)"
```

Override the bundled analysis prompt (for multi-file reasoning)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-bundle-analyze-prompt "$(cat prompts/bundle_analyze_prompt.txt)"
```

Override the file filtering prompt (affects which files are analyzed)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-filter-prompt 'Select only application source files that may declare HTTP routes or middleware.'
```

Notes and caveats

- Hidden flags are intended for development and may be removed or changed without notice.
- Output may be unstable or differ significantly across runs, depending on the prompt content and LLM behavior.
- If your shell expands characters unexpectedly, prefer single quotes for literal strings or read prompts from files.
- Ensure your environment is configured for LLM-backed features if your workflow relies on optimization steps.

Screenshot examples

Without override flag

```bash
./bin/noir -b ./spec/functional_test/fixtures/crystal/kemal --ai-provider=lmstudio --ai-model=kanana-nano-2.1b-instruct --exclude-techs kemal --cache-disable
```

![No hidden flag result](images/noflag.jpg)

With --override-analyze-prompt

```bash
./bin/noir -b ./spec/functional_test/fixtures/crystal/kemal --ai-provider=lmstudio --ai-model=kanana-nano-2.1b-instruct --exclude-techs kemal --cache-disable --override-analyze-prompt "This is custom prompt for testttttt"
```

![With hidden flag result](images/withflag.jpg)
