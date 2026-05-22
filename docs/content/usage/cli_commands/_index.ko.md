+++
title = "CLI 명령어"
description = "Noir v1 서브커맨드 표면 — scan, list, cache, config, rules, completion, version, help — 레퍼런스."
weight = 1
sort_by = "weight"

+++

v1.0부터 Noir CLI는 동사 중심 구조를 따릅니다. `scan` 이 가장 자주 쓰는
주 동작이고, 나머지는 작은 네임스페이스(`list`, `cache`, `config`,
`rules`)로 묶여 있습니다.

```
noir <command> [arguments] [flags]
```

## 빠른 참조

| 명령어                  | 설명                                                   |
|------------------------|--------------------------------------------------------|
| `noir scan PATHS...`   | 하나 이상의 코드베이스에서 엔드포인트 탐지              |
| `noir list techs`      | 지원하는 언어/프레임워크/분석기 목록                    |
| `noir list taggers`    | 빌트인/프레임워크별 태거 목록                           |
| `noir list formats`    | 지원하는 출력 형식 목록                                 |
| `noir cache info`      | LLM 캐시 디렉토리·항목 수·크기 표시                     |
| `noir cache clear`     | 캐시된 AI 응답 전체 삭제                                |
| `noir config show`     | 활성 설정 파일 출력                                     |
| `noir config edit`     | `$VISUAL` / `$EDITOR` 로 설정 파일 열기                 |
| `noir config init`     | 기본 설정 파일 생성 (멱등)                              |
| `noir config path`     | 해석된 설정 경로 출력                                   |
| `noir rules list`      | 룰 경로에 설치된 룰 파일 목록                           |
| `noir rules update`    | 최신 passive-scan 룰을 클론/풀                          |
| `noir rules path`      | 설정된 룰 디렉토리 출력                                 |
| `noir completion zsh`  | Zsh/Bash/Fish/Elvish 자동 완성 스크립트 생성            |
| `noir version`         | 버전 출력 (`--verbose` 시 빌드 세부 정보)               |
| `noir help [command]`  | 최상위 또는 명령어별 도움말 표시                        |

## Scan

`noir scan` 이 핵심 워크호스입니다. 하나 이상의 코드베이스를 워크하면서
탐지된 기술별 분석기를 돌리고, 옵션에 따라 passive scanner도 함께
실행한 다음, 지정한 출력 형식으로 엔드포인트를 리포팅합니다.

```bash
# 단일 코드베이스 스캔
noir scan ./app

# 한 번의 호출로 여러 코드베이스 스캔
noir scan ./api ./worker ./jobs

# JSON으로 파일 저장 + passive scan
noir scan ./app -P -f json -o endpoints.json

# 전체 AI 컨텍스트 + path/techs/callee 인리치먼트
noir scan ./app --include path,techs,callee --ai-context
```

positional path와 반복 `-b PATH` 는 동치라 스크립트에서 자연스럽게
보이는 쪽을 쓰면 됩니다.

### v1의 플래그 통합

v0의 일부 플래그 패밀리는 v1.0에서 더 간결한 형태로 통합되었습니다.
v1.x 전 구간에서 옛 형태는 silent alias 로 계속 동작합니다.

| v1 형식                                     | v0 등가 (계속 동작)                       |
|--------------------------------------------|-----------------------------------------|
| `--pvalue query=FOO`                       | `--set-pvalue-query FOO`                |
| `--pvalue header=X`                        | `--set-pvalue-header X`                 |
| `--pvalue FOO` (`TYPE=` 없음)              | `--set-pvalue FOO`                      |
| `--include path,techs,callee`              | `--include-path --include-techs --include-callee` |
| `--ai-context guards,sinks`                | `--ai-context` (필터 없음, 전체 출력)   |
| `noir version --verbose`                   | `--build-info`                          |
| `noir completion zsh`                      | `--generate-completion zsh`             |
| `noir list techs`                          | `--list-techs`                          |
| `noir list taggers`                        | `--list-taggers`                        |
| `noir help`                                | `--help-all`                            |

### v1.0에서 제거된 항목

`--ollama` / `--ollama-model` 은 여러 릴리즈에 걸쳐 deprecated 상태였고
v1.0에서 완전히 제거되었습니다. 대신 `--ai-provider ollama [--ai-model NAME]`
를 사용하세요:

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## List

`noir list` 는 빌트인 카탈로그를 열거합니다. `update` 같은 동사가
영원히 생기지 않을 정적 데이터라, 하나의 네임스페이스 안에 subject 로
머무릅니다.

```bash
noir list techs       # Noir 가 지원하는 언어/프레임워크/스펙
noir list taggers     # 빌트인 + 프레임워크별 태거
noir list formats     # 지원되는 모든 출력 형식
```

## Cache

`noir cache` 는 디스크에 저장된 LLM 응답 캐시(`~/.config/noir/cache/ai`)를
관리합니다.

```bash
noir cache info       # 경로/항목 수/총 크기
noir cache clear      # 캐시된 AI 응답 전체 삭제
```

스캔 도중 동작 제어는 그대로 `noir scan` 에 있습니다 — `--cache-disable`
은 1회 실행에서 캐시를 건너뛰고, `--cache-clear` 는 스캔 전에 캐시를
비웁니다.

## Config

`noir config` 는 사용자 레벨 YAML 설정을 관리합니다.

```bash
noir config show      # 활성 파일 출력
noir config edit      # $VISUAL / $EDITOR 로 열기
noir config init      # 기본 설정 생성 (멱등)
noir config path      # 해석된 경로 출력
```

설정 디렉토리는 `NOIR_HOME` 이 있으면 그 값을 따르고, 없으면 Unix에서는
`$HOME/.config/noir`, Windows 에서는 `%APPDATA%\noir` 로 폴백합니다.

`noir config edit` 는 `$VISUAL`, `$EDITOR`, 그리고 플랫폼 기본값
(Unix: `vi`, Windows: `notepad`) 순서로 에디터를 결정합니다. 설정
파일이 없으면 먼저 기본 파일을 만든 뒤 엽니다.

## Rules

`noir rules` 는 passive-scan 룰 저장소를 관리합니다.

```bash
noir rules list       # 설치된 룰 파일 목록
noir rules update     # 최신 룰을 클론하거나 풀
noir rules path       # 룰 디렉토리 출력
```

기본 룰 경로는 `~/.config/noir/passive_rules` — `NOIR_HOME` 또는 스캔
시점의 `--passive-scan-path PATH` 로 재정의할 수 있습니다.

## Completion

`noir completion <shell>` 은 지정한 쉘의 자동 완성 스크립트를
출력합니다.

```bash
noir completion zsh    > "${fpath[1]}/_noir"
noir completion bash   > /etc/bash_completion.d/noir
noir completion fish   > ~/.config/fish/completions/noir.fish
noir completion elvish > ~/.config/elvish/lib/noir.elv  # rc.elv 에서 `use noir`
```

스크립트는 서브커맨드를 인식합니다. `noir <TAB>` 은 동사를, `noir scan
-<TAB>` 은 scan 플래그를 완성합니다. Elvish 버전은 동일한 표면을
`$edit:completion:arg-completer[noir]` 에 등록합니다.

## Version

`noir version` 은 버전 번호만 출력하고, `noir version --verbose` 는
Crystal/LLVM/타깃 트리플 등 빌드 세부 정보(v0 `--build-info` 내용 그대로)를
추가합니다.

## Help

`noir help` 는 최상위 개요를, `noir help <command>` 는 해당 명령어의
플래그 표면을 보여줍니다.

## 글로벌 플래그

`scan` 뿐 아니라 모든 서브커맨드에서 동작하는 플래그:

| 플래그        | 효과                                                                 |
|--------------|----------------------------------------------------------------------|
| `--no-color` | 모든 명령의 출력에서 ANSI 색상 제거 (`NO_COLOR` 환경변수도 반영)      |
| `-h`, `--help` | 현재 명령의 도움말 표시                                            |

명령어별 플래그(출력 형식, 동시성, passive scan, AI provider 등)는
`noir scan` 아래에 있으며 `noir help scan` 으로 확인할 수 있습니다.

## v0 호환성

v0의 모든 호출 패턴은 v1.x 에서 변경 없이 그대로 동작합니다:

```bash
# 세 형태 모두 동일한 스캔 결과를 만듭니다
noir -b ./app                # v0 (라우터가 scan 으로 default-route)
noir scan ./app              # v1 idiomatic
noir scan -b ./app           # v1 명시 + v0-형 플래그
```

라우터는 `ARGV[0]` 이 알려진 동사가 아니면 `scan` 으로 폴백하므로 CI
파이프라인, GitHub Action, Dockerfile entrypoint, 쉘 alias 모두 수정
없이 v1.0 으로 넘어갑니다.

deprecation 경고는 추후 v1.x 시리즈에서 도입되며, 동사 형식이 의무가
되는 시점은 v2.x 입니다.
