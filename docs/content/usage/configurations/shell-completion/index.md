+++
title = "Shell Completions"
description = "Set up shell auto-completion for Noir in Zsh, Bash, Fish, and Elvish."
weight = 2
sort_by = "weight"

+++

Press `Tab` to auto-complete Noir's commands, flags, and options. Noir can generate completion scripts for four shells.

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

## Elvish

[Elvish](https://elv.sh) loads completions from its module path. Save the script as `noir.elv` and `use` it from your `rc.elv`:

```bash
mkdir -p ~/.config/elvish/lib
noir completion elvish > ~/.config/elvish/lib/noir.elv
echo 'use noir' >> ~/.config/elvish/rc.elv
```

Once loaded, the completer registers at `$edit:completion:arg-completer[noir]`. `noir <Tab>` lists the verbs, `noir scan <Tab>` falls back to filesystem paths, and `noir scan -<Tab>` lists scan flags.

## Homebrew Users

If you installed Noir via Homebrew, completions are already set up; nothing to do here.
