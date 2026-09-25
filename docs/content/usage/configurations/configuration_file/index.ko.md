+++
title = "설정 파일 사용하기"
description = "config.yaml 파일로 Noir 기본 옵션을 설정합니다."
weight = 1
sort_by = "weight"

+++

`config.yaml` 파일로 기본 옵션을 설정하여 일관된 스캔을 수행할 수 있습니다.

## 파일 위치

| OS | 경로 |
|---|---|
| macOS | `~/.config/noir/` |
| Linux | `~/.config/noir/` |
| Windows | `%APPDATA%\noir\` |

설정 파일의 값은 명령줄 인자로 재정의할 수 있습니다. 기본 위치가 아닌 곳에서 설정을 불러오려면 `--config-file <경로>`를 사용하세요:

```bash
noir scan . --config-file ./ci/noir.yaml
```

설정 파일은 `noir config` 로도 직접 다룰 수 있습니다:

```bash
noir config init   # 기본 설정 생성 (멱등)
noir config show   # 활성 파일 출력
noir config edit   # $VISUAL / $EDITOR 로 파일 열기
noir config path   # 해석된 경로 출력
```

## 디렉터리 구조

```
~/.config/noir/
├── config.yaml          # 설정 파일
├── cache/
│   └── ai/              # LLM 응답 캐시
└── passive_rules/       # 패시브 스캔 규칙
```

## `config.yaml` 예제

```yaml
---
# 스캔의 기본 베이스 경로
base: "/path/to/my/project"

# 출력에서 항상 색상 사용
color: true

# 기본 출력 형식
format: "json"

# 프로브 대상 기본 URL. exclude_codes / status_codes / probe 에도 필요합니다
url: "https://api.example.com"

# 특정 상태 코드 제외 (대상 URL이 있어야 하므로 위 `url`과 함께 씁니다)
exclude_codes: "404,500"

# 기본적으로 모든 태거 활성화
all_taggers: true

# 엔드포인트마다 1-hop 핸들러 callee 첨부
include_callee: true

# AI 리뷰 컨텍스트(guards, callee, sources, sinks, validators, signals) 첨부
ai_context: true

# 기본 AI 제공업체 및 모델
ai_provider: "openai"
ai_model: "gpt-5.5"

# 패시브 보안 스캔 (-P / --passive-scan 과 동일)
passive_scan: false
passive_scan_severity: "high"

# 분석기가 실패했거나 건너뛴 파일이 있으면 종료 코드 2
strict: false

# 로딩 스피너 애니메이션 비활성화
no_spinner: false

# 발견된 엔드포인트에 HTTP 프로브 실행 (`url` 필요)
probe: false

# 프로브/내보내기 시 TLS 인증서 검증 건너뛰기 (비보안)
tls_skip_verify: false
```

위 설정은 다음 명령과 동일합니다:

```bash
noir scan /path/to/my/project -f json -u https://api.example.com --exclude-codes "404,500" -T \
  --include callee --ai-context \
  --ai-provider openai --ai-model gpt-5.5
```

## 키 참고

`noir config init` 는 지원하는 모든 키가 주석으로 달린 파일을 만듭니다. 위 예시는 자주 쓰는 기본값만 보여 주며, CLI 플래그가 항상 설정 파일보다 우선합니다. 아래 키 이름은 생성 파일과 동일합니다(v0 의 `send_es` / `send_proxy` 같은 옛 이름도 읽히지만 v1 이름으로 옮기는 것이 좋습니다).

### 스캔 경로와 범위

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `base` | string 또는 list | positional 경로 / `-b` | 기본 스캔 경로 |
| `url` | string | `-u` / `--url` | 경로 앞에 붙는 기본 URL. status/probe 옵션에 필요 |
| `exclude_path` | CSV glob | `--exclude-path` | 매치되는 파일 건너뛰기 |
| `techs` | CSV | `-t` / `--techs` | 자동 탐지에 더해 분석기 집합에 기술 추가 |
| `only_techs` | CSV | `--only-techs` | 실행할 기술 디텍터 제한 |
| `exclude_techs` | CSV | `--exclude-techs` | 탐지 후 최종 집합에서 기술 제거 |
| `concurrency` | int | `--concurrency` | 워커 수 |

### 출력

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `format` | string | `-f` / `--format` | `plain`, `json`, `yaml`, `oas3`, `curl`, … |
| `output` | string | `-o` / `--output` | 결과 파일 경로 |
| `color` | bool | `--no-color` 의 반대 | plain 출력 ANSI 색상 |
| `nolog` | bool | `--no-log` | 결과만 표시 |
| `no_spinner` | bool | `--no-spinner` | 스피너 애니메이션 비활성화 |
| `strict` | bool | `--strict` | 분석기 실패/파일 스킵 시 종료 코드 `2` |
| `status_codes` | bool | `--status-codes` | 프로브 후 HTTP 상태 코드 첨부 (`url` 필요) |
| `exclude_codes` | CSV | `--exclude-codes` | 프로브 상태 제외 (`status_codes` 와 함께) |
| `include_path` | bool | `--include path` | `--include` 의 레거시 bool 형태 |
| `include_techs` | bool | `--include techs` | `--include` 의 레거시 bool 형태 |
| `include_callee` | bool | `--include callee` | 1-hop 핸들러 callee 첨부 |
| `ai_context` | bool | `--ai-context` | AI 리뷰 컨텍스트 첨부 |
| `ai_context_features` | CSV | `--ai-context LIST` | 부분 집합: `guards`, `callee`, `sources`, `sinks`, `validators`, `signals` |

### 파라미터 값

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `set_pvalue` | list | `--pvalue any=…` | 모든 파라미터 타입 값 채우기 |
| `set_pvalue_header` | list | `--pvalue header=…` | 헤더 값 |
| `set_pvalue_cookie` | list | `--pvalue cookie=…` | 쿠키 값 |
| `set_pvalue_query` | list | `--pvalue query=…` | 쿼리 값 |
| `set_pvalue_form` | list | `--pvalue form=…` | 폼 값 |
| `set_pvalue_json` | list | `--pvalue json=…` | JSON 본문 값 |
| `set_pvalue_path` | list | `--pvalue path=…` | 경로 값 |

### 패시브 스캔과 태거

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `passive_scan` | bool | `-P` / `--passive-scan` | 패시브 스캔 활성화 |
| `passive_scan_path` | list | `--passive-scan-path` | 커스텀 규칙 디렉터리(번들 규칙 대체) |
| `passive_scan_severity` | string | `--passive-scan-severity` | `critical` / `high` / `medium` / `low` |
| `passive_scan_auto_update` | bool | `--passive-scan-auto-update` | 시작 시 규칙 업데이트 |
| `passive_scan_no_update_check` | bool | `--passive-scan-no-update-check` | 업데이트 확인 건너뛰기 |
| `all_taggers` | bool | `-T` / `--use-all-taggers` | 모든 태거 활성화 |
| `use_taggers` | CSV | `--use-taggers` | 선택한 태거만 활성화 |

### 프로브와 내보내기

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `probe` | bool | `--probe` | 발견된 엔드포인트에 HTTP 요청 (`url` 필요) |
| `probe_via` | string | `--probe-via` | 프로브용 프록시 URL |
| `probe_header` | list | `--probe-header` | 추가 프로브 헤더 |
| `probe_match` | list | `--probe-match` | 매치되는 엔드포인트만 프로브 |
| `probe_skip` | list | `--probe-skip` | 매치되는 엔드포인트 건너뛰기 |
| `tls_skip_verify` | bool | `--tls-skip-verify` | 프로브/내보내기/웹훅 TLS 검증 건너뛰기 |
| `export_es` | string | `--export-es` / `--export-opensearch` | Elasticsearch 또는 OpenSearch URL (두 플래그 모두 이 키에 기록) |
| `export_webhook` | string | `--export-webhook` | 카탈로그 JSON 을 POST 할 URL |

### AI 와 캐시

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `ai_provider` | string | `--ai-provider` | 제공업체 접두사 또는 전체 URL |
| `ai_model` | string | `--ai-model` | 모델 이름 |
| `ai_key` | string | `--ai-key` / `NOIR_AI_KEY` | 공유 설정에서는 환경 변수 권장 |
| `ai_agent` | bool | `--ai-agent` | 에이전트형 tool-calling 루프 활성화 |
| `ai_agent_max_steps` | int | `--ai-agent-max-steps` | 에이전트 루프 상한 |
| `ai_native_tools_allowlist` | CSV | `--ai-native-tools-allowlist` | 네이티브 툴 사용을 허용할 제공업체 |
| `ai_max_token` | int | `--ai-max-token` | 요청당 최대 토큰 (`0` = 제공업체 기본값) |
| `cache_disable` | bool | `--cache-disable` | LLM 응답 캐시 비활성화 |
| `cache_clear` | bool | `--cache-clear` | 실행 전 캐시 비우기 |

### Diff 와 진단

| 키 | 타입 | CLI 대응 | 설명 |
|---|---|---|---|
| `diff` | string | `--diff-path` | diff 출력용 이전 코드 경로 |
| `config_file` | string | `--config-file` | 보통 CLI 로만 지정 |
| `debug` | bool | `-d` / `--debug` | 디버그 로깅 |
| `verbose` | bool | `--verbose` | 상세 로깅 (`--include path` + 모든 태거) |


