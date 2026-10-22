+++
title = "셸 자동완성"
description = "Zsh, Bash, Fish, Elvish에서 Noir 셸 자동완성을 설정합니다."
weight = 2
sort_by = "weight"

+++

`Tab` 키로 Noir의 명령어, 플래그, 옵션을 자동완성할 수 있습니다. Noir는 네 가지 셸용 완성 스크립트를 만들어 줍니다.

## Zsh

생성되는 완성 스크립트를 미리 봅니다.

```bash
noir completion zsh
```

자동으로 불러오게 하려면 스크립트를 완성 디렉터리에 저장하고, `compinit`이 실행되기 전에 그 디렉터리가 Zsh의 `fpath`에 들어 있게 하세요.

```bash
mkdir -p ~/.zsh/completion
noir completion zsh > ~/.zsh/completion/_noir
```

그다음 `~/.zshrc`에서 `compinit` 호출 전에 이 디렉터리를 `fpath`에 추가하세요. `site-functions`처럼 이미 `fpath`에 있는 디렉터리에 저장했다면 이 단계는 필요 없습니다.

```bash
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit
```

## Bash

생성되는 완성 스크립트를 미리 봅니다.

```bash
noir completion bash
```

`bash-completion` 표준 디렉터리에 저장하면 새 세션부터 자동으로 불러옵니다.

```bash
mkdir -p ~/.local/share/bash-completion/completions
noir completion bash > ~/.local/share/bash-completion/completions/noir
```

## Fish

생성되는 완성 스크립트를 미리 봅니다.

```bash
noir completion fish
```

Fish의 완성 디렉터리에 저장하면 자동으로 불러옵니다.

```bash
mkdir -p ~/.config/fish/completions
noir completion fish > ~/.config/fish/completions/noir.fish
```

## Elvish

[Elvish](https://elv.sh)는 모듈 경로에서 완성 스크립트를 불러옵니다. 스크립트를 `noir.elv`로 저장하고 `rc.elv`에 `use noir`를 추가하세요.

```bash
mkdir -p ~/.config/elvish/lib
noir completion elvish > ~/.config/elvish/lib/noir.elv
echo 'use noir' >> ~/.config/elvish/rc.elv
```

불러오면 `$edit:completion:arg-completer[noir]`에 완성기가 등록됩니다. `noir <Tab>`은 동사 목록을, `noir scan <Tab>`은 파일 경로를, `noir scan -<Tab>`은 scan 플래그를 보여줍니다.

## Homebrew 사용자

Homebrew로 설치했다면 셸 자동완성이 이미 설정되어 있어 별도 작업이 필요 없습니다.
