+++
title = "Troubleshooting"
description = "Solutions for common issues when using OWASP Noir."
weight = 2
sort_by = "weight"

+++

## No Endpoints Found

**Symptom:** Noir runs but reports 0 endpoints.

- Check that you are pointing to the correct directory: `noir -b ./your-app`
- Verify that your framework is supported: `noir --list-techs`
- Try scanning with `--verbose` to see which technologies were detected
- If your framework is not supported, use [AI-Powered Analysis](@/get_started/ai_power/index.md) to detect endpoints

## Scan Takes Too Long

**Symptom:** Noir takes a long time on large codebases.

- Use `--techs` to limit scanning to specific frameworks: `noir -b . --techs rails`
- Use `--exclude-techs` to skip known irrelevant frameworks
- AI-powered analysis caches responses — subsequent runs on the same codebase will be faster

## AI Provider Connection Errors

**Symptom:** Errors when using `--ai-provider`.

- Verify your API key is correct: `--ai-key <KEY>` or set `NOIR_AI_KEY` environment variable
- For local providers (Ollama, vLLM, LM Studio), ensure the server is running
- Check the provider's default host in the [AI Providers](@/usage/ai_providers/_index.md) table
- For custom endpoints, use the full URL: `--ai-provider=http://your-server:port`
- Enable debug logs with `NOIR_ACP_RAW_LOG=1` for ACP providers

## Docker Permission Issues

**Symptom:** Permission denied errors when running via Docker.

- Ensure your directory is mounted correctly: `docker run --rm -v $(pwd):/tmp ghcr.io/owasp-noir/noir:latest -b /tmp`
- On SELinux systems, add `:z` to the volume mount: `-v $(pwd):/tmp:z`

## Shell Completion Not Working

**Symptom:** Tab completion doesn't work after installation.

- If installed via Homebrew, completions are installed automatically
- For manual setup, see [Shell Completions](@/usage/configurations/shell-completion/index.md)
- After setting up, restart your shell or run `source ~/.zshrc` (or equivalent)

## Still Need Help?

- Open a [GitHub Issue](https://github.com/owasp-noir/noir/issues)
- See the [Contact](@/resources/contact/index.md) page for more ways to reach the team
