---
title: Shell Completion
parent: Tips
has_children: false
nav_order: 2
layout: page
---

## Zsh completion

To enable auto-completion for Zsh, run the following command to generate the completion script:

```bash
noir --generate-completion zsh
# #compdef noir
# _arguments \
# ....
```

Then, move the generated script to your Zsh completions directory, typically `~/.zsh/completion/`. If this directory does not exist, you may need to create it. Ensure the script is named `_noir` to follow Zsh's naming convention for completion scripts.

```bash
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash completion

For Bash, generate the completion script by running:

```bash
noir --generate-completion bash
# _noir_completions() {
#     local cur prev opts
# ....
```

After generating the script, move it to the appropriate directory for Bash completions. This location can vary depending on your operating system and Bash configuration, but a common path is `/etc/bash_completion.d/` for system-wide availability, or `~/.local/share/bash-completion/completions/` for a single user. Ensure the script is executable and sourced in your Bash profile.

```bash
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish completion

For Fish, generate the completion script by running:

```bash
noir --generate-completion fish
# function __fish_noir_needs_command
# ....
```

After generating the script, move it to the Fish completions directory, typically `~/.config/fish/completions/.` If this directory does not exist, you may need to create it. Ensure the script is named noir.fish to follow Fish's naming convention for completion scripts.

```bash
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```