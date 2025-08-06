+++
title = "Shell Completions"
description = "Improve your productivity by enabling shell auto-completion for Noir. This guide provides instructions for setting up completions in Zsh, Bash, and Fish."
weight = 2
sort_by = "weight"

[extra]
+++

Shell completion is a powerful feature that can make you more efficient when using the command line. By enabling it for Noir, you can get suggestions for commands and flags as you type, which helps reduce typos and saves you from having to memorize every option.

Noir can generate completion scripts for several popular shells. Here's how to set them up.

## Zsh

To enable auto-completion for Zsh, you first need to generate the completion script:

```bash
noir --generate-completion zsh
```

This will output the script to your terminal. To make it active, you need to save it to your Zsh completions directory. A common location is `~/.zsh/completion/`. Make sure to name the file `_noir` to follow Zsh's conventions.

```bash
# Create the directory if it doesn't exist
mkdir -p ~/.zsh/completion

# Save the script to the correct location
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash

For Bash, the process is similar. First, generate the script:

```bash
noir --generate-completion bash
```

The location for Bash completion scripts can vary, but a good place for user-specific completions is `~/.local/share/bash-completion/completions/`. You'll want to save the script there.

```bash
# Create the directory if it doesn't exist
mkdir -p ~/.local/share/bash-completion/completions

# Save the script
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

For the Fish shell, generate the script like this:

```bash
noir --generate-completion fish
```

Fish keeps its completion scripts in `~/.config/fish/completions/`. You should save the output to a file named `noir.fish` in that directory.

```bash
# Create the directory if it doesn't exist
mkdir -p ~/.config/fish/completions

# Save the script
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew Users

If you installed Noir using Homebrew, shell completions are automatically installed for you. There's no need for any additional setup—they should work out of the box.
