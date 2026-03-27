+++
title = "셸 자동완성"
description = "Zsh, Bash, Fish에서 Noir 셸 자동완성을 설정합니다."
weight = 2
sort_by = "weight"

+++

`Tab` 키를 누르면 Noir의 명령어, 플래그, 옵션이 자동완성됩니다. 주요 셸별로 완성 스크립트를 생성할 수 있습니다.

## Zsh

아래 명령으로 생성될 완성 스크립트를 미리 확인할 수 있습니다.

```bash
noir --generate-completion zsh
```

Zsh이 시작할 때 자동으로 로드하려면, 완성 디렉터리에 저장합니다.

```bash
mkdir -p ~/.zsh/completion
noir --generate-completion zsh > ~/.zsh/completion/_noir
```

## Bash

마찬가지로 먼저 미리 확인할 수 있습니다.

```bash
noir --generate-completion bash
```

`bash-completion` 표준 디렉터리에 저장하면 새 세션에서 자동으로 로드됩니다.

```bash
mkdir -p ~/.local/share/bash-completion/completions
noir --generate-completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

미리 확인합니다.

```bash
noir --generate-completion fish
```

Fish의 완성 디렉터리에 저장하면 자동 로드됩니다.

```bash
mkdir -p ~/.config/fish/completions
noir --generate-completion fish > ~/.config/fish/completions/noir.fish
```

## Homebrew 사용자

Homebrew로 설치했다면 셸 자동완성이 이미 설정되어 있어 별도 작업이 필요 없습니다.
