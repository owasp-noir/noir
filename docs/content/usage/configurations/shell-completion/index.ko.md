+++
title = "셸 자동완성"
description = "Zsh, Bash, Fish에서 Noir 셸 자동완성을 설정합니다."
weight = 2
sort_by = "weight"

+++

명령어와 플래그에 대한 셸 자동완성을 활성화합니다.

## Zsh

자동완성 스크립트 생성:

```bash
noir --generate-completion zsh
```

자동완성 디렉터리에 저장:

```bash
mkdir -p ~/.zsh/completion
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash

스크립트 생성:

```bash
noir --generate-completion bash
```

자동완성 디렉터리에 저장:

```bash
mkdir -p ~/.local/share/bash-completion/completions
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

스크립트 생성:

```bash
noir --generate-completion fish
```

자동완성 디렉터리에 저장:

```bash
mkdir -p ~/.config/fish/completions
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew 사용자

Homebrew로 설치한 경우 셸 자동완성이 자동으로 설치됩니다.