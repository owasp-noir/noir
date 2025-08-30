+++
title = "셸 자동완성"
description = "Noir를 위한 셸 자동완성을 활성화하여 생산성을 향상시키세요. 이 가이드는 Zsh, Bash, Fish에서 자동완성을 설정하는 지침을 제공합니다."
weight = 2
sort_by = "weight"

[extra]
+++

셸 자동완성은 명령줄을 사용할 때 더 효율적으로 만들어주는 강력한 기능입니다. Noir에 대해 활성화하면 입력하는 동안 명령어와 플래그에 대한 제안을 받을 수 있어 오타를 줄이고 모든 옵션을 기억할 필요가 없습니다.

Noir는 여러 인기 있는 셸에 대한 자동완성 스크립트를 생성할 수 있습니다. 설정 방법은 다음과 같습니다.

## Zsh

Zsh에 대한 자동완성을 활성화하려면 먼저 자동완성 스크립트를 생성해야 합니다:

```bash
noir --generate-completion zsh
```

이렇게 하면 스크립트가 터미널에 출력됩니다. 활성화하려면 Zsh 자동완성 디렉토리에 저장해야 합니다. 일반적인 위치는 `~/.zsh/completion/`입니다. Zsh의 규칙에 따라 파일 이름을 `_noir`로 지정해야 합니다.

```bash
# 디렉토리가 없으면 생성
mkdir -p ~/.zsh/completion

# 스크립트를 올바른 위치에 저장
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash

Bash의 경우 과정은 비슷합니다. 먼저 스크립트를 생성합니다:

```bash
noir --generate-completion bash
```

Bash 자동완성 스크립트의 위치는 다양할 수 있지만, 사용자별 자동완성을 위한 좋은 장소는 `~/.local/share/bash-completion/completions/`입니다. 스크립트를 거기에 저장하세요.

```bash
# 디렉토리가 없으면 생성
mkdir -p ~/.local/share/bash-completion/completions

# 스크립트 저장
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

Fish 셸의 경우 다음과 같이 스크립트를 생성합니다:

```bash
noir --generate-completion fish
```

Fish는 자동완성 스크립트를 `~/.config/fish/completions/`에 보관합니다. 해당 디렉토리에 `noir.fish`라는 이름의 파일로 출력을 저장해야 합니다.

```bash
# 디렉토리가 없으면 생성
mkdir -p ~/.config/fish/completions

# 스크립트 저장
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew 사용자

Homebrew를 사용하여 Noir를 설치했다면 셸 자동완성이 자동으로 설치됩니다. 추가 설정이 필요하지 않으며 바로 작동합니다.