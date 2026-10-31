+++
title = "CLI 명령어"
description = "Noir v1 서브커맨드(scan, trace, reach, query, list, cache, config, rules, completion, version, help) 레퍼런스."
weight = 1
sort_by = "weight"

+++

v1.0부터 Noir CLI는 동사 기반 구조를 씁니다. 핵심 명령은 `scan`이고,
질의 명령(`trace`, `reach`, `query`)과 몇 개의 네임스페이스(`list`, `cache`, `config`, `rules`)가
나머지를 묶습니다.

```
noir <command> [arguments] [flags]
```

## 빠른 참조

| 명령어                  | 설명                                                   |
|------------------------|--------------------------------------------------------|
| `noir scan PATHS...`   | 하나 이상의 코드베이스에서 엔드포인트 탐지              |
| `noir trace "<METHOD> <URL>"` | 요청을 라우트·가드·파라미터·싱크로 매핑          |
| `noir reach FILE[:LINE]` | 소스 파일에 닿는 엔드포인트 목록                      |
| `noir query [FILTERS]` | AND 조건 필터로 공격 표면 검색                          |
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
| `noir rules list`      | 규칙 경로에 설치된 규칙 파일 목록                           |
| `noir rules update`    | 최신 패시브 스캔 규칙을 clone 또는 pull                   |
| `noir rules path`      | 설정된 규칙 디렉터리 출력                                 |
| `noir completion zsh`  | Zsh / Bash / Fish / Elvish 자동완성 스크립트 생성       |
| `noir version`         | 버전 출력 (`--verbose`를 붙이면 빌드 정보 추가)         |
| `noir help [command]`  | 전체 도움말 또는 명령어별 도움말                        |

## Scan

`noir scan`은 하나 이상의 코드베이스를 훑으면서 탐지된 기술마다
분석기를 실행합니다. 필요하면 패시브 스캔도 함께 돌리고, 지정한 출력 형식으로
엔드포인트를 출력합니다.

```bash
# 단일 코드베이스 스캔
noir scan ./app

# 한 번에 여러 코드베이스 스캔
noir scan ./api ./worker ./jobs

# JSON으로 파일 저장 + 패시브 스캔
noir scan ./app -P -f json -o endpoints.json

# AI 컨텍스트 전체 + plain 출력에 path/techs/callee 포함
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
| BASE | `-b/--base-path`, `-u/--url` | [첫 번째 스캔](@/get_started/running/index.ko.md) |
| OUTPUT | `-f/--format`, `-o/--output`, `--pvalue`, `--status-codes`, `--exclude-codes`, `--exclude-path`, `--include`, `--ai-context`, `--no-color`, `--no-spinner`, `--no-log`, `--strict` | [출력 형식](@/usage/output_formats/_index.ko.md), [AI 컨텍스트 커버리지](@/usage/supported/ai_context_coverage/index.ko.md) |
| PASSIVE SCAN | `-P/--passive-scan`, `--passive-scan-path`, `--passive-scan-severity`, `--passive-scan-auto-update`, `--passive-scan-no-update-check` | [패시브 스캔](@/usage/passive_scan/_index.ko.md) |
| TAGGER | `-T/--use-all-taggers`, `--use-taggers` | [태거](@/usage/more_features/tagger/index.ko.md) |
| PROBE | `--probe`, `--probe-via`, `--probe-header`, `--probe-match`, `--probe-skip`, `--tls-skip-verify` | [Deliver](@/usage/more_features/deliver/index.ko.md) |
| EXPORT | `--export-es`, `--export-opensearch`, `--export-webhook` | [Deliver](@/usage/more_features/deliver/index.ko.md) |
| AI Integration | `--ai-provider`, `--ai-model`, `--ai-key`, `--ai-key-file`, `--ai-temperature`, `--ai-seed`, `--ai-agent`, `--ai-agent-max-steps`, `--ai-dry-run`, `--ai-include-sensitive`, `--ai-no-optimize`, `--ai-native-tools-allowlist`, `--ai-scope`, `--ai-max-token`, `--ai-stream`, `--ai-max-requests` | [AI 제공업체](@/usage/ai_providers/_index.ko.md), [AI 기반 분석](@/get_started/ai_power/index.ko.md) |
| DIFF | `--diff-path`, `--diff-ref`, `--fail-on` | [Diff](@/usage/more_features/diff/index.ko.md) |
| TECHNOLOGIES | `-t/--techs`, `--only-techs`, `--exclude-techs` | [기술 범위 관리](@/usage/supported/tech-commands/index.ko.md) |
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

`--ollama`와 `--ollama-model`은 여러 릴리스 동안 지원 중단 상태였다가
v1.0에서 제거되었습니다. 대신 `--ai-provider ollama [--ai-model NAME]`을
쓰세요.

```bash
noir scan ./app --ai-provider ollama --ai-model llama3
```

## Trace, Reach, Query

엔드포인트를 나열하는 대신 추적하기 위한 질의 명령 세 개입니다. AI 에이전트(또는
특정 질문을 가진 리뷰어)에게 필요한 형태로, 좁은 질문을 던지면 작은 답을
돌려줍니다. 각 명령은 `--ai-context all --include callee`가 적용된 스캔을 실행하며
`scan`의 모든 플래그를 받습니다. `--from`으로 저장된 리포트를 읽으면 스캔 한 번으로
여러 질문에 답할 수 있습니다.

```bash
noir scan ./app -f json --ai-context --include callee -o report.json   # 한 번만

noir trace "POST /api/users/42" --from report.json     # 요청 → 라우트, 가드, 파라미터, 싱크, callee
noir reach src/handlers/users.go:57 --from report.json # 파일 → 그 파일에 선언되거나 호출하는 엔드포인트
noir query --no-guard --sink any --from report.json    # 인증 없이 임의의 싱크에 닿는 라우트
```

### Trace

```bash
noir trace "<METHOD> <URL>" [paths...] [flags]
noir trace <URL> [paths...] [flags]              # 해당 경로의 모든 HTTP 메서드
```

`trace`는 실제 요청 경로를 선언된 라우트에 대응시킵니다. `/api/users/42`는
`/api/users/{id}`, `:id`, `<int:pk>`, `[id]`, `*`에 매칭되고, HEAD 요청은 GET
라우트에 대응됩니다. 메서드를 생략하면 해당 경로의 모든 메서드에 대해 매칭되는
라우트를 찾습니다. `noir trace "POST /api/users/42" ./app`처럼 스캔 대상 경로를
직접 전달할 수도 있습니다.

매칭되는 라우트를 구체적인 순서로 전부 출력하며 `matched_by`(`exact`, `pattern`,
`wildcard`, 그리고 프록시 접두사 규칙이나 Go ServeMux의 `/x/` 하위 트리의 경우
`prefix`)를 함께 표시합니다. 기본 형식인 `jsonl`과 `json`에서는 `endpoint` 아래에
전체 엔드포인트 레코드를 출력하며, 텍스트 형식(`-f text`)에서는 한 줄 요약으로
출력합니다.

매칭이 없으면 가장 가까운 라우트를 `candidates`(공통 접두사 세그먼트 수, 다른
세그먼트 간의 편집 거리, 경로 길이 차이 기준 정렬)로 출력한 뒤 종료 코드 1을
반환합니다. `jsonl`과 `json`에서는 `{"query": "<label>", "match": false, "candidates": [...]}`
형태로 출력되며, `text`에서는 `no match: <label>` 뒤에 후보 목록이 출력됩니다.
와일드카드나 접두사 라우트(`/*unmatched_route` 등)만 매칭된 경우에도 요청 경로의
오타 가능성을 고려하여 매칭 결과 뒤에 후보 목록이 함께 출력됩니다.

### Reach

```bash
noir reach <FILE[:LINE]> [paths...] [flags]
```

`reach`는 `FILE`을 경로 접미사로 보고 Noir가 기록한 모든 위치(라우트 선언, 핸들러
정의, callee, 가드, 소스, 싱크, 검증기)와 비교해 근거를 `via`(`kind:name@line` 또는
`kind@line`)에 나열합니다. 행의 파일이 아닌 곳의 근거에는 경로(`@path:line`)가
붙습니다. `:LINE`을 주면 근거와 행을 거리순으로 정렬하고 `nearest_line`을 채웁니다.
Noir는 함수 범위가 아니라 선언 줄만 기록하므로, 줄 번호는 필터가 아니라 정렬
기준입니다. 상속과 동적 로딩은 따라가지 않습니다.

기록된 위치 중 `FILE`과 매칭되는 곳이 없으면 stderr에 설명 힌트를 출력하고 종료
코드 1을 반환합니다. `:LINE`을 지정했으나 해당 파일의 근거에 줄 번호가 기록되어
있지 않은 경우 stderr에 안내 메시지를 출력합니다.

### Query

```bash
noir query [filters] [paths...] [flags]
```

`query`의 필터는 AND로 결합됩니다.

쉼표 목록으로 여러 값을 주면 OR 조건으로 매칭되는 필터:
- `--method GET,POST`: HTTP 메서드 (`--method POST`는 `ANY`로 선언된 라우트도 매칭하며, `--method ANY`는 `ANY` 라우트만 매칭)
- `--project <dir,...>`: 스캔 기준 경로에 상대적인 모노레포 프로젝트 디렉터리 (정확히 일치하거나, `*`, `?`, `[` 포함 시 글롭 매칭)
- `--tech <name,...>`: 기술 이름 (예: `go_gin`, `python_django`)
- `--tag <name,...>`: 태그 이름 (`auth`, `admin` 등)
- `--param <name,...>`: 파라미터 이름 (헤더 파라미터는 대소문자 구분 없음)
- `--param-type <type,...>`: 파라미터 위치/유형 (`query`, `json`, `form`, `header`, `cookie`, `path`)
- `--protocol <proto,...>`: 프로토콜 (`http`, `ws`, `cli` 등)
- `--sink <kind,...|any>`: 해당 유형의 싱크에 도달 (`sql`, `command`, `file_io`, `outbound_http`, `template_render`, `redirect`, `mass_assignment` 등)
- `--source <kind,...|any>`: 해당 유형의 소스를 읽음
- `--signal <kind,...|any>`: 파생 보안 리뷰 신호 포함 (`idor_review`, `ssrf`, `open_redirect` 등)
- `--validator <kind,...|any>`: 해당 유형의 검증기 포함

단일 패턴을 받는 필터 (`<glob|substr>`):
- `--url <glob|substr>`: 라우트 URL
- `--path <glob|substr>`: 보고된 소스 파일 경로 (상대 글롭은 임의의 `/` 뒤에서도 매칭)
- `--handler <glob|substr>`: 핸들러 함수 이름 또는 핸들러 소스 파일 경로

불리언 스위치 (상호 배타적):
- `--guard` / `--no-guard`: 인증 가드(`ai_context.guards`) 존재 여부 (rate limiter와 CSRF 검사는 가드로 치지 않음)

패턴 매칭 규칙:
- 글롭 문자(`*`, `?`, `[`): `*`는 `/`를 넘어 매칭되고 `{id}`는 글자 그대로 비교됩니다. 글롭 문자가 없으면 부분 문자열로 매칭됩니다.
- `--param`과 `--param-type`: 같은 하나의 파라미터가 두 조건을 모두 만족해야 합니다.
- `any` 키워드: `--sink`, `--source`, `--signal`, `--validator`에서 `any`는 해당 버킷이 비어 있지 않으면 매칭됩니다.
- stderr 경고: 리포트에 없는 값을 필터에 지정하면 stderr에 리포트에 실제 존재하는 값 목록과 함께 경고를 출력합니다. `--ai-context` 없이 스캔된 리포트에 `--guard`나 `--sink` 같은 컨텍스트 필터를 적용하면 AI 컨텍스트가 없다는 경고를 출력합니다.

### 공통 플래그 및 종료 코드

세 질의 명령 모두 다음 옵션을 지원합니다:

| 플래그 | 설명 |
|--------|------|
| `--from <report>` | 스캔을 실행하는 대신 `noir scan -f json` 또는 `-f jsonl` 리포트 파일 읽기 |
| `-f, --format <fmt>` | 출력 형식: `jsonl` (기본값), `json`, `text` (`plain`은 `text`의 별칭) |
| `--full` | `jsonl` 및 `json`에서 `matched_by`, `via`, `nearest_line`과 함께 `endpoint`에 전체 엔드포인트 레코드 포함. `text`에서는 항상 한 줄 요약 유지 |
| `--limit <n>` | 최대 n개 행 출력 (양의 정수여야 하며, candidates 개수도 제한) |
| `--count` | 매칭된 엔드포인트 개수만 출력 |
| 스캔 플래그 | `--from` 없이 직접 스캔할 때 모든 `noir scan` 플래그(`-b`, `--exclude-path`, `--only-techs`, `-t`, `-u`, `--config-file` 등) 사용 가능 |

`--from`을 지정하면 아무것도 스캔하지 않으므로 스캔 경로나 스캔 플래그를 함께 전달하면 사용법 오류(종료 코드 2)가 발생합니다. 전역 플래그(`--no-color`, `-d`, `--verbose`)는 `--from`과 함께 사용할 수 있습니다.

종료 코드는 grep 규칙을 따릅니다:
- `0`: 하나 이상의 엔드포인트가 매칭됨.
- `1`: 매칭된 결과 없음 (trace 미스, reach에서 해당 파일에 닿는 엔드포인트 없음, query 매칭 결과 0건).
- `2`: 사용법 오류 (잘못된 플래그, 필수 인자 누락, 상호 배타적 플래그 동시 사용, 양의 정수가 아닌 `--limit`, `--from`과 함께 스캔 인자 전달, 리포트 읽기 실패).

### 출력 행 형식

기본 압축 행(`-f jsonl`)은 엔드포인트 레코드의 투영이며 빈 버킷은 생략됩니다:

```json
{"method":"POST","url":"/api/users/{id}","path":"src/routes.go","line":42,"tech":"go_gin",
 "handler":{"name":"updateUser","path":"src/users.go","line":80},
 "params":["id:path","name:json"],"guards":["RequireAuth"],"sinks":["sql"],
 "signals":["idor_review"],"callees":["db.Exec","render"]}
```

- `path:line`: 라우트가 선언된 곳 (복사본이 병합된 경우 복사 디렉터리 밖의 첫 파일이며, 병합된 복사본이 둘 이상이면 `declarations`에 개수 표시).
- `project`: 스캔 기준 경로에 상대적인 모노레포 프로젝트 디렉터리 (없으면 생략).
- `handler`: 핸들러 본문 위치 (`name`, `path`, `line`, 분석기가 정의 위치를 찾은 경우).
- `params`: `name:type` 형식의 파라미터 목록.
- `guards`: 인증 및 인가 가드 (rate limiter, CSRF 제외).
- `sinks`, `signals`: 프레임워크 인식 싱크 종류 및 파생 보안 리뷰 신호.
- `matched_by`: `trace`에서 추가 (`exact`, `pattern`, `wildcard`, `prefix`).
- `via`: `reach`에서 추가 (`route`, `handler`, `callee`, `guard`, `source`, `sink`, `validator` 근거 목록).
- `nearest_line`: `reach`에 `:LINE`을 지정했을 때 추가.

텍스트 형식(`-f text`)에서는 각 엔드포인트를 공백으로 구분된 한 줄로 출력합니다:

```text
POST /api/users/{id}  src/routes.go:42  go_gin  handler=updateUser@src/users.go:80  guards=RequireAuth  sinks=sql  signals=idor_review
```

이 명령들과 스캔 한 번 후 `--from`으로 질의하는 루프, 에이전트가 알아야 할 주의점을
정리한 에이전트 스킬이 [`skills/noir/SKILL.md`](https://github.com/owasp-noir/noir/blob/main/skills/noir/SKILL.md)에
있습니다. 에이전트의 스킬 디렉터리에 복사해 사용하세요.

## List

`noir list`는 내장 카탈로그를 출력합니다.

```bash
noir list techs       # 지원하는 언어, 프레임워크, 스펙
noir list taggers     # 기본 태거와 프레임워크별 태거
noir list formats     # 지원하는 모든 출력 형식
noir list techs -f json   # 기계가 읽는 형식. -f는 text(기본), json, yaml
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
noir config show      # 현재 설정 파일 출력
noir config edit      # $VISUAL / $EDITOR로 열기
noir config init      # 기본 설정 생성 (여러 번 실행해도 안전)
noir config path      # 최종 경로 출력
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

`noir rules`는 패시브 스캔 규칙 저장소를 관리합니다.

```bash
noir rules list       # 설치된 규칙 파일 목록
noir rules update     # 최신 규칙을 clone 또는 pull
noir rules path       # 규칙 디렉터리 출력
```

기본 규칙 경로는 `~/.config/noir/passive_rules`입니다. `NOIR_HOME`으로
바꾸거나, 스캔할 때 `--passive-scan-path PATH`로 다른 경로를 지정할 수
있습니다.

## Completion

`noir completion <shell>`은 지정한 셸의 자동완성 스크립트를 출력합니다.

```bash
noir completion zsh    > "${fpath[1]}/_noir"
mkdir -p ~/.local/share/bash-completion/completions
noir completion bash   > ~/.local/share/bash-completion/completions/noir
mkdir -p ~/.config/fish/completions
noir completion fish   > ~/.config/fish/completions/noir.fish
mkdir -p ~/.config/elvish/lib
noir completion elvish > ~/.config/elvish/lib/noir.elv  # 그 다음 rc.elv에서 `use noir`
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

`--no-color`와 `--no-spinner`는 동사 앞뒤 어디에 두어도 됩니다.
`noir --no-color list techs`와 `noir list techs --no-color`는 같은 명령입니다.
`-v`/`--version`은 동사 앞에서만 동작합니다. 동사 뒤에서는 `noir version`을
쓰세요(`noir rules update -v`의 `-v`는 verbose입니다).

명령어별 플래그(출력 형식, 동시성, 패시브 스캔, AI 제공업체 등)는
`noir scan`에 있습니다. 전체 목록은 `noir help scan`으로 볼 수 있습니다.

## v0 호환성

v0의 호출 방식은 v1.x에서 수정 없이 그대로 동작합니다.

```bash
# 세 형태 모두 같은 스캔 결과를 냅니다
noir -b ./app                # v0 형식 (scan으로 라우팅)
noir scan ./app              # v1 형식
noir scan -b ./app           # v1 동사 + v0 스타일 플래그
```

글로벌 플래그를 뺀 첫 인자가 알려진 동사가 아니면 Noir는 `scan`을
실행합니다. CI 파이프라인, GitHub Actions, Dockerfile entrypoint, 셸
alias를 고치지 않아도 됩니다.

지원 중단 경고는 이후 v1.x 릴리스에서 추가됩니다. 동사 형식이
필수가 되는 것은 v2.x부터입니다.
