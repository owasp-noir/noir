+++
title = "Debug with hidden flags"
description = "Developer-only flags not shown in --help for debugging and experimentation"
weight = 3
sort_by = "weight"

+++

Developer-only flags that do not appear in `--help` output. Names, behavior, and availability may change without notice.

Available flags

- `--override-analyze-prompt` — Overrides the internal ANALYZE_PROMPT for individual file analysis.
- `--override-llm-optimize-prompt` — Overrides the internal LLM_OPTIMIZE_PROMPT for endpoint optimization.
- `--override-bundle-analyze-prompt` — Overrides the internal BUNDLE_ANALYZE_PROMPT for bundled (multi-file) analysis.
- `--override-filter-prompt` — Overrides the internal FILTER_PROMPT for file filtering.

When to use these flags

- Testing new prompt strategies for analysis, filtering, or optimization
- Rapidly iterating without rebuilding
- Comparing prompt variations' impact on output quality

Usage tips

- Quote prompt strings to preserve spaces and special characters.
- For multi-line prompts, read from a file with command substitution.
- Validate with a small fixture directory before scaling up.
- Combine with `--verbose` to inspect intermediate steps.

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

Override the bundled analysis prompt (multi-file reasoning)

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-bundle-analyze-prompt "$(cat prompts/bundle_analyze_prompt.txt)"
```

Override the file filtering prompt

```bash
./bin/noir -b spec/functional_test/fixtures/crystal \
  --override-filter-prompt 'Select only application source files that may declare HTTP routes or middleware.'
```

Notes and caveats

- Hidden flags may be removed or changed without notice.
- Output may vary across runs depending on prompt content and LLM behavior.
- Use single quotes for literal strings if your shell expands characters unexpectedly, or read prompts from files.
- Ensure LLM environment is configured (API keys, etc.) if your workflow relies on optimization steps.

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
