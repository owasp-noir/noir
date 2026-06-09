+++
title = "CLI 명령어"
description = "Noir v1 서브커맨드(scan, list, cache, config, rules, completion, version, help) 레퍼런스."
weight = 1
sort_by = "weight"

+++

v1.0부터 Noir CLI는 동사 기반 구조를 따릅니다. `scan` 이 핵심 명령이고,
나머지는 작은 네임스페이스(`list`, `cache`, `config`, `rules`)로
묶입니다.

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
| `noir cache info`      | LLM 캐시 디렉토리, 항목 수, 크기 표시                   |
| `noir cache clear`     | 캐시된 AI 응답 전체 삭제                                |
| `noir config show`     | 활성 설정 파일 출력                                     |
| `noir config edit`     | `$VISUAL` / `$EDITOR` 로 설정 파일 열기                 |
| `noir config init`     | 기본 설정 파일 생성 (멱등)                              |
| `noir config path`     | 해석된 설정 경로 출력                                   |
| `noir rules list`      | 룰 경로에 설치된 룰 파일 목록                           |
| `noir rules update`    | 최신 passive-scan 룰을 클론 또는 풀                     |
| `noir rules path`      | 설정된 룰 디렉토리 출력                                 |
| `noir completion zsh`  | Zsh / Bash / Fish / Elvish 자동완성 스크립트 생성       |
| `noir version`         | 버전 출력 (`--verbose` 는 빌드 세부 정보 추가)          |
| `noir help [command]`  | 최상위 또는 명령어별 도움말                             |

## Scan

`noir scan` 은 하나 이상의 코드베이스를 순회하면서 탐지된 기술별
분석기를 실행하고, 필요하면 passive scanner도 함께 돌린 뒤 지정한
형식으로 엔드포인트를 출력합니다.

```bash
# 단일 코드베이스 스캔
noir scan ./app

# 한 번의 호출로 여러 코드베이스 스캔
noir scan ./api ./worker ./jobs

# JSON 으로 파일 저장 + passive scan
noir scan ./app -P -f json -o endpoints.json

# 전체 AI 컨텍스트 + path/techs/callee enrichment
noir scan ./app --include path,techs,callee --ai-context
```

positional path 와 반복 `-b PATH` 는 동일하게 동작합니다. 스크립트에서
읽기 좋은 쪽을 쓰면 됩니다.

> 여러 코드베이스는 positional (`noir scan ./api ./worker`) 이든 반복
> `-b` 든 sibling root 로 스코프되며, 이것이 지원되는 모노레포 형태입니다.
> 중첩되거나 겹치는 root (예: `noir scan /repo /repo/sub`)에서는 정의와
> 사용처가 서로 다른 longest-matching root 로 해석될 수 있어 cross-base
> prefix 가 합성되지 않습니다. sibling 레이아웃을 권장합니다.

### v1 의 플래그 통합

v0 의 몇몇 플래그 패밀리가 v1.0 에서 더 짧은 형태로 통합되었습니다.
옛 형태는 v1.x 전 구간에서 silent alias 로 계속 동작합니다.

| v1 형식                                     | v0 등가 (계속 동작)                       |
|--------------------------------------------|-----------------------------------------|
| `--probe`                                  | `--send-req`                            |
| `--probe-via URL`                          | `--send-proxy URL`                      |
| `--probe-header VAL`                       | `--with-headers VAL`                    |
| `--probe-match VAL`                        | `--use-matchers VAL`                    |
| `--probe-skip VAL`                         | `--use-filters VAL`                     |
| `--export-es URL`                          | `--send-es URL`                         |
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

Deliver family 는 `noir scan -h` 에서 두 가지 semantic 섹션으로 분리되었습니다. **PROBE** 는 발견된 endpoint 로 active HTTP replay 를 수행하고, **EXPORT** 는 endpoint catalog 을 외부 데이터 저장소 (Elasticsearch, OpenSearch, webhook) 로 ship 합니다. 전체 표면은 [다른 도구로 결과 전송하기](@/usage/more_features/deliver/index.ko.md) 를, 배경과 v1 에서 추가된 export 들은 [v0 에서 v1 로 마이그레이션](@/get_started/migrate_v0_to_v1/index.ko.md) 을 참고하세요.

### v1.0 에서 제거된 항목

`--ollama` / `--ollama-model` 은 여러 릴리즈에 걸쳐 deprecated 상태였고
v1.0 에서 완전히 제거되었습니다. 대신 `--ai-provider ollama
[--ai-model NAME]` 을 사용하세요.

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## List

`noir list` 는 빌트인 카탈로그를 보여줍니다. `update` 같은 동작이
생길 일이 없는 정적 데이터라, 하나의 네임스페이스 아래 subject 로
유지됩니다.

```bash
noir list techs       # 지원하는 언어, 프레임워크, 스펙
noir list taggers     # 빌트인 및 프레임워크별 태거
noir list formats     # 지원하는 모든 출력 형식
```

## Cache

`noir cache` 는 디스크에 저장되는 LLM 응답 캐시
(`~/.config/noir/cache/ai`)를 관리합니다.

```bash
noir cache info       # 경로, 항목 수, 총 크기
noir cache clear      # 캐시된 AI 응답 전체 삭제
```

스캔 도중 캐시 제어는 그대로 `noir scan` 에 있습니다. `--cache-disable`
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

설정 디렉토리는 `NOIR_HOME` 이 있으면 그 값을 따릅니다. 없으면 Unix
에서는 `$HOME/.config/noir`, Windows 에서는 `%APPDATA%\noir` 로
폴백합니다.

`noir config edit` 는 `$VISUAL`, `$EDITOR`, 플랫폼 기본값(Unix: `vi`,
Windows: `notepad`) 순서로 에디터를 결정합니다. 설정 파일이 없으면
먼저 기본 파일을 만든 뒤 엽니다.

## Rules

`noir rules` 는 passive-scan 룰 저장소를 관리합니다.

```bash
noir rules list       # 설치된 룰 파일 목록
noir rules update     # 최신 룰을 클론하거나 풀
noir rules path       # 룰 디렉토리 출력
```

기본 룰 경로는 `~/.config/noir/passive_rules` 입니다. `NOIR_HOME` 또는
스캔 시점의 `--passive-scan-path PATH` 로 재정의할 수 있습니다.

## Completion

`noir completion <shell>` 은 지정한 쉘의 자동완성 스크립트를
출력합니다.

```bash
noir completion zsh    > "${fpath[1]}/_noir"
noir completion bash   > /etc/bash_completion.d/noir
noir completion fish   > ~/.config/fish/completions/noir.fish
noir completion elvish > ~/.config/elvish/lib/noir.elv  # 그 다음 rc.elv 에서 `use noir`
```

스크립트는 모든 서브커맨드를 인식합니다. `noir <TAB>` 은 동사 목록을,
`noir scan -<TAB>` 은 scan 플래그를 보여줍니다. Elvish 버전은 동일한
완성기를 `$edit:completion:arg-completer[noir]` 에 등록합니다.

## Version

`noir version` 은 버전 번호만 출력합니다. `noir version --verbose` 는
Crystal, LLVM, 타깃 트리플 등 빌드 세부 정보를 추가합니다(v0
`--build-info` 가 출력하던 내용 그대로).

## Help

`noir help` 는 최상위 개요를, `noir help <command>` 는 해당 명령어의
플래그 목록을 보여줍니다.

## 글로벌 플래그

`scan` 뿐 아니라 모든 서브커맨드에서 동작하는 플래그:

| 플래그          | 효과                                                                 |
|----------------|----------------------------------------------------------------------|
| `--no-color`   | 모든 명령의 출력에서 ANSI 색상 제거 (`NO_COLOR` 환경변수도 반영)      |
| `-v, --version`| Noir 버전 출력 후 종료                                                |
| `-h, --help`   | 현재 명령의 도움말 표시                                              |

명령어별 플래그(출력 형식, 동시성, passive scan, AI provider 등)는
`noir scan` 아래에 있습니다. `noir help scan` 으로 전체 목록을 볼 수
있습니다.

## v0 호환성

v0 의 모든 호출 패턴은 v1.x 에서 변경 없이 그대로 동작합니다.

```bash
# 세 형태 모두 동일한 스캔 결과를 만듭니다
noir -b ./app                # v0 형식 (scan 으로 라우팅)
noir scan ./app              # v1 형식
noir scan -b ./app           # v1 동사 + v0 스타일 플래그
```

`ARGV[0]` 가 알려진 동사가 아니면 라우터가 `scan` 으로 폴백합니다. CI
파이프라인, GitHub Action, Dockerfile entrypoint, 쉘 alias 가 수정
없이 그대로 동작합니다.

deprecation 경고는 추후 v1.x 시리즈에서 추가됩니다. 동사 형식이
의무가 되는 시점은 v2.x 입니다.
