+++
title = "CLI 명령어"
description = "Noir v1 서브커맨드(scan, list, cache, config, rules, completion, version, help) 레퍼런스."
weight = 1
sort_by = "weight"

+++

v1.0부터 Noir CLI는 동사 기반 구조를 씁니다. 핵심 명령은 `scan`이고,
나머지는 몇 개의 네임스페이스(`list`, `cache`, `config`, `rules`)로
묶여 있습니다.

```
noir <command> [arguments] [flags]
```

## 빠른 참조

| 명령어                  | 설명                                                   |
|------------------------|--------------------------------------------------------|
| `noir scan PATHS...`   | 하나 이상의 코드베이스에서 엔드포인트 탐지              |
| `noir list techs`      | 지원하는 언어, 프레임워크, 분석기 목록                  |
| `noir list taggers`    | 기본 태거와 프레임워크별 태거 목록                      |
| `noir list formats`    | 지원하는 출력 형식 목록                                 |
| `noir cache info`      | LLM 캐시 디렉터리, 항목 수, 크기 표시                   |
| `noir cache clear`     | 캐시된 AI 응답 전체 삭제                                |
| `noir cache purge <days>` | N일보다 오래된 캐시 항목 삭제                         |
| `noir config show`     | 현재 사용 중인 설정 파일 출력                           |
| `noir config edit`     | `$VISUAL` / `$EDITOR`로 설정 파일 열기                  |
| `noir config init`     | 기본 설정 파일 생성 (여러 번 실행해도 안전)             |
| `noir config path`     | 설정 파일 경로 출력                                     |
| `noir rules list`      | 룰 경로에 설치된 룰 파일 목록                           |
| `noir rules update`    | 최신 패시브 스캔 룰을 clone 또는 pull                   |
| `noir rules path`      | 설정된 룰 디렉터리 출력                                 |
| `noir completion zsh`  | Zsh / Bash / Fish / Elvish 자동완성 스크립트 생성       |
| `noir version`         | 버전 출력 (`--verbose`를 붙이면 빌드 정보 추가)         |
| `noir help [command]`  | 전체 도움말 또는 명령어별 도움말                        |

## Scan

`noir scan`은 하나 이상의 코드베이스를 훑으면서 탐지된 기술마다
분석기를 실행합니다. 필요하면 패시브 스캔도 함께 돌리고, 지정한 포맷으로
엔드포인트를 출력합니다.

```bash
# 단일 코드베이스 스캔
noir scan ./app

# 한 번에 여러 코드베이스 스캔
noir scan ./api ./worker ./jobs

# JSON 으로 파일 저장 + passive scan
noir scan ./app -P -f json -o endpoints.json

# 전체 AI 컨텍스트 + path/techs/callee enrichment
noir scan ./app --include path,techs,callee --ai-context
```

경로를 인자로 바로 넘기든 `-b PATH`를 반복하든 동작은 같습니다.
스크립트에서 읽기 편한 쪽을 쓰세요.

> 여러 코드베이스는 나란히 있는 형제 루트로 넘기세요(`noir scan ./api ./worker`
> 또는 `-b` 반복). 이것이 지원하는 모노레포 형태입니다. 중첩되거나 겹치는
> 루트(예: `noir scan /repo /repo/sub`)에서는 라우트 정의와 사용처가 서로
> 다른 루트로 잡힐 수 있어서, 베이스를 넘나드는 경로 prefix를 합치지 않습니다.

### Scan 플래그

`noir scan -h`는 플래그를 아래 섹션으로 나눠 보여줍니다. 섹션마다
자세한 설명이 있는 페이지가 따로 있습니다.

| 섹션 | 플래그 | 자세히 |
|------|--------|--------|
| BASE | `-b/--base-path`, `-u/--url` | [Noir 실행하기](@/get_started/running/index.ko.md) |
| OUTPUT | `-f/--format`, `-o/--output`, `--pvalue`, `--status-codes`, `--exclude-codes`, `--exclude-path`, `--include`, `--ai-context`, `--no-color`, `--no-spinner`, `--no-log`, `--strict` | [출력 형식](@/usage/output_formats/_index.ko.md), [AI 컨텍스트 커버리지](@/usage/supported/ai_context_coverage/index.ko.md) |
| PASSIVE SCAN | `-P/--passive-scan`, `--passive-scan-path`, `--passive-scan-severity`, `--passive-scan-auto-update`, `--passive-scan-no-update-check` | [패시브 스캔](@/usage/passive_scan/_index.ko.md) |
| TAGGER | `-T/--use-all-taggers`, `--use-taggers` | [태거](@/usage/more_features/tagger/index.ko.md) |
| PROBE | `--probe`, `--probe-via`, `--probe-header`, `--probe-match`, `--probe-skip`, `--tls-skip-verify` | [Deliver](@/usage/more_features/deliver/index.ko.md) |
| EXPORT | `--export-es`, `--export-opensearch`, `--export-webhook` | [Deliver](@/usage/more_features/deliver/index.ko.md) |
| AI Integration | `--ai-provider`, `--ai-model`, `--ai-key`, `--ai-key-file`, `--ai-temperature`, `--ai-seed`, `--ai-agent`, `--ai-agent-max-steps`, `--ai-dry-run`, `--ai-include-sensitive`, `--ai-no-optimize`, `--ai-native-tools-allowlist`, `--ai-scope`, `--ai-max-token`, `--ai-stream`, `--ai-max-requests` | [AI 제공업체](@/usage/ai_providers/_index.ko.md), [AI 기반 분석](@/get_started/ai_power/index.ko.md) |
| DIFF | `--diff-path`, `--diff-ref`, `--fail-on` | [Diff](@/usage/more_features/diff/index.ko.md) |
| TECHNOLOGIES | `-t/--techs`, `--only-techs`, `--exclude-techs` | [기술 명령어](@/usage/supported/tech-commands/index.ko.md) |
| CONFIG | `--config-file`, `--concurrency` | [설정 파일](@/usage/configurations/configuration_file/index.ko.md) |
| CACHE | `--cache-disable`, `--cache-clear` | 아래 [Cache](#cache) |
| DEBUG | `-d/--debug`, `--verbose`, `-h/--help` | `--verbose`는 `--include path`와 `--use-all-taggers`도 함께 켭니다 |

스캔이 성공하면 종료 코드는 `0`입니다. `--strict`를 주면 분석기가 실패했거나
파일을 건너뛰었을 때 `2`로 끝납니다. `--fail-on`을 주면 diff 스캔에서 지정한
변경 종류가 나왔을 때 `3`으로 끝납니다. 두 경우 모두 리포트는 먼저 끝까지
씁니다.

### v1의 플래그 통합

v0의 일부 플래그 묶음이 v1.0에서 더 짧은 형태로 합쳐졌습니다. 예전
형태도 v1.x 동안에는 경고 없이 그대로 동작합니다.

| v1 형식                                     | v0 형식 (계속 동작)                       |
|--------------------------------------------|-----------------------------------------|
| `--probe`                                  | `--send-req`                            |
| `--probe-via URL`                          | `--send-proxy URL`                      |
| `--probe-header VAL`                       | `--with-headers VAL`                    |
| `--probe-match VAL`                        | `--use-matchers VAL`                    |
| `--probe-skip VAL`                         | `--use-filters VAL`                     |
| `--export-es URL`                          | `--send-es URL`                         |
| `--pvalue query=FOO`                       | `--set-pvalue-query FOO`                |
| `--pvalue header=X`                        | `--set-pvalue-header X`                 |
| `--pvalue cookie=X`                        | `--set-pvalue-cookie X`                 |
| `--pvalue form=X`                          | `--set-pvalue-form X`                   |
| `--pvalue json=X`                          | `--set-pvalue-json X`                   |
| `--pvalue path=X`                          | `--set-pvalue-path X`                   |
| `--pvalue FOO` (`TYPE=` 없음)              | `--set-pvalue FOO`                      |
| `--include path,techs,callee`              | `--include-path --include-techs --include-callee` |
| `--ai-context guards,sinks`                | `--ai-context` (필터 없음, 전체 출력)   |
| `noir version --verbose`                   | `--build-info`                          |
| `noir completion zsh`                      | `--generate-completion zsh`             |
| `noir list techs`                          | `--list-techs`                          |
| `noir list taggers`                        | `--list-taggers`                        |
| `noir help`                                | `--help-all`                            |

v0의 deliver 플래그는 이제 `noir scan -h`에서 두 섹션으로 나뉩니다. **PROBE**는 발견한 엔드포인트로 HTTP 요청을 보내고, **EXPORT**는 엔드포인트 목록을 외부 저장소(Elasticsearch, OpenSearch, webhook)로 보냅니다. 전체 플래그는 [다른 도구로 결과 전송하기](@/usage/more_features/deliver/index.ko.md)를, 바뀐 이유와 v1에서 새로 생긴 export는 [v0에서 v1로 마이그레이션](@/get_started/migrate_v0_to_v1/index.ko.md)을 참고하세요.

### v1.0에서 제거된 항목

`--ollama`와 `--ollama-model`은 여러 릴리스 동안 deprecated 상태였다가
v1.0에서 제거되었습니다. 대신 `--ai-provider ollama [--ai-model NAME]`을
쓰세요.

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## List

`noir list`는 내장 카탈로그를 출력합니다.

```bash
noir list techs       # 지원하는 언어, 프레임워크, 스펙
noir list taggers     # 빌트인 및 프레임워크별 태거
noir list formats     # 지원하는 모든 출력 형식
noir list techs -f json   # 기계가 읽는 형식. -f 는 text(기본), json, yaml 을 받습니다
```

## Cache

`noir cache`는 디스크에 저장되는 LLM 응답 캐시
(`~/.config/noir/cache/ai`)를 관리합니다.

```bash
noir cache info       # 경로, 항목 수, 총 크기
noir cache clear      # 캐시된 AI 응답 전체 삭제
noir cache purge 30   # 30일보다 오래된 항목 삭제
```

스캔할 때 쓰는 캐시 옵션은 `noir scan`에 그대로 있습니다. `--cache-disable`은
그 실행에서만 캐시를 쓰지 않고, `--cache-clear`는 스캔 전에 캐시를 비웁니다.

## Config

`noir config`는 사용자 수준의 YAML 설정을 관리합니다.

```bash
noir config show      # 활성 파일 출력
noir config edit      # $VISUAL / $EDITOR 로 열기
noir config init      # 기본 설정 생성 (멱등)
noir config path      # 해석된 경로 출력
```

설정 디렉터리는 `NOIR_HOME`이 있으면 그 값을 씁니다. 없으면 Unix에서는
`$HOME/.config/noir`, Windows에서는 `%APPDATA%\noir`를 씁니다.

`noir config edit`는 `$VISUAL`, `$EDITOR`, 플랫폼 기본값(Unix는 `vi`,
Windows는 `notepad`) 순서로 에디터를 고릅니다. 설정 파일이 아직 없으면
먼저 만든 뒤 엽니다.

기본 파일이 아닌 다른 설정 파일을 쓰려면 `show`, `edit`, `path`에
`--config-file PATH`를 넘기세요.

```bash
noir config show --config-file ./ci/noir.yaml   # 특정 파일 출력
noir config path --config-file ./ci/noir.yaml   # 절대 경로 해석
```

`init`은 항상 기본 파일을 만들고 `--config-file`은 무시합니다.

## Rules

`noir rules`는 패시브 스캔 룰 저장소를 관리합니다.

```bash
noir rules list       # 설치된 룰 파일 목록
noir rules update     # 최신 룰을 클론하거나 풀
noir rules path       # 룰 디렉터리 출력
```

기본 룰 경로는 `~/.config/noir/passive_rules`입니다. `NOIR_HOME`으로
바꾸거나, 스캔할 때 `--passive-scan-path PATH`로 다른 경로를 지정할 수
있습니다.

## Completion

`noir completion <shell>`은 지정한 셸의 자동완성 스크립트를 출력합니다.

```bash
noir completion zsh    > "${fpath[1]}/_noir"
mkdir -p ~/.local/share/bash-completion/completions
noir completion bash   > ~/.local/share/bash-completion/completions/noir
noir completion fish   > ~/.config/fish/completions/noir.fish
noir completion elvish > ~/.config/elvish/lib/noir.elv  # 그 다음 rc.elv 에서 `use noir`
```

스크립트는 모든 서브커맨드를 알고 있습니다. `noir <TAB>`은 동사 목록을,
`noir scan -<TAB>`은 scan 플래그를 완성합니다. Elvish 스크립트는
`$edit:completion:arg-completer[noir]`에 완성기를 등록합니다. 셸별 설정
방법은 [셸 자동완성](@/usage/configurations/shell-completion/index.ko.md)을
참고하세요.

## Version

`noir version`은 버전 번호만 출력합니다. `noir version --verbose`는
Crystal, LLVM, 타깃 트리플 같은 빌드 정보를 함께 보여줍니다(v0의
`--build-info`와 같은 내용).

## Help

`noir help`는 전체 개요를, `noir help <command>`는 해당 명령어의
플래그를 보여줍니다.

## 글로벌 플래그

다음 플래그는 `scan`뿐 아니라 모든 서브커맨드에서 동작합니다.

| 플래그          | 효과                                                                 |
|----------------|----------------------------------------------------------------------|
| `--no-color`   | 모든 명령의 출력에서 ANSI 색상 제거 (`NO_COLOR` 환경 변수도 인식)     |
| `--no-spinner` | 로그는 그대로 두고 로딩 스피너만 끔                                   |
| `-v`, `-V`, `--version` | Noir 버전을 출력하고 종료                                    |
| `-h`, `--help` | 현재 명령의 도움말 표시                                              |

동사 앞뒤 어디에 두어도 됩니다. `noir --no-color list techs`와
`noir list techs --no-color`는 같은 명령입니다.

명령어별 플래그(출력 형식, 동시성, 패시브 스캔, AI 제공업체 등)는
`noir scan`에 있습니다. 전체 목록은 `noir help scan`으로 볼 수 있습니다.

## v0 호환성

v0의 호출 방식은 v1.x에서 수정 없이 그대로 동작합니다.

```bash
# 세 형태 모두 동일한 스캔 결과를 만듭니다
noir -b ./app                # v0 형식 (scan 으로 라우팅)
noir scan ./app              # v1 형식
noir scan -b ./app           # v1 동사 + v0 스타일 플래그
```

글로벌 플래그를 뺀 첫 인자가 알려진 동사가 아니면 Noir는 `scan`을
실행합니다. CI 파이프라인, GitHub Actions, Dockerfile entrypoint, 셸
alias를 고치지 않아도 됩니다.

deprecation 경고는 이후 v1.x 릴리스에서 추가됩니다. 동사 형식이
필수가 되는 것은 v2.x부터입니다.
