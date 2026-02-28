+++
title = "Shell Completions"
description = "Set up shell auto-completion for Noir in Zsh, Bash, and Fish."
weight = 2
sort_by = "weight"

+++

Enable shell auto-completion for commands and flags.

## Zsh

Generate completion script:

```bash
noir --generate-completion zsh
```

Save to completions directory:

```bash
mkdir -p ~/.zsh/completion
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash

Generate script:

```bash
noir --generate-completion bash
```

Save to completions directory:

```bash
mkdir -p ~/.local/share/bash-completion/completions
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

Generate script:

```bash
noir --generate-completion fish
```

Save to completions directory:

```bash
mkdir -p ~/.config/fish/completions
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew Users

Shell completions are automatically installed with Homebrew.
