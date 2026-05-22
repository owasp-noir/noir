+++
title = "Shell Completions"
description = "Set up shell auto-completion for Noir in Zsh, Bash, and Fish."
weight = 2
sort_by = "weight"

+++

Press `Tab` to auto-complete Noir's commands, flags, and options. Noir can generate completion scripts for the three most popular shells.

## Zsh

Preview the generated completion script:

```bash
noir completion zsh
```

To load it automatically, save the script to a completions directory that Zsh picks up on startup:

```bash
mkdir -p ~/.zsh/completion
noir completion zsh > ~/.zsh/completion/_noir
```

## Bash

Preview the generated completion script:

```bash
noir completion bash
```

Save it to the standard `bash-completion` directory so new sessions load it automatically:

```bash
mkdir -p ~/.local/share/bash-completion/completions
noir completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

Preview the generated completion script:

```bash
noir completion fish
```

Save it to Fish's completions directory for automatic loading:

```bash
mkdir -p ~/.config/fish/completions
noir completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew Users

If you installed Noir via Homebrew, completions are already set up; nothing to do here.
