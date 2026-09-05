+++
title = "v0 에서 v1 로 마이그레이션"
description = "Noir 0.x 와 1.0 사이의 변경점: 플래그, 설정 키, 동작 변화, 그리고 v0 스크립트를 그대로 돌아가게 하는 호환 계층."
weight = 5
sort_by = "weight"

+++

{% mascot(mood="question") %}
거의 모든 v0 호출은 v1 에서 그대로 동작해. 이 페이지는 이름이 바뀐 것, 동작이 달라진 것, 명시적으로 깨진 항목 몇 가지를 한 곳에 모아둔 정리야.
{% end %}

이 가이드는 훑어보기 좋게 구성했습니다. 아래 요약부터 보고, 실제로 스크립트나 대시보드가 건드리는 CLI·플래그·출력 섹션만 골라서 보면 됩니다.

## 요약

v1.0 은 **호환성을 최우선**으로 삼았습니다. `noir -b ./app -P -f json` 같은 v0 호출은 자동으로 `scan` 서브커맨드로 라우팅되고, 이름이 바뀐 모든 플래그는 옛 이름을 별칭으로 그대로 받습니다. 명시적으로 깨진 것은 2024년부터 deprecated 상태였던 `--ollama` / `--ollama-model` 뿐이며, `--ai-provider ollama [--ai-model NAME]` 으로 대체합니다.

업그레이드만 하고 계속 쓸 거라면 여기까지만 읽어도 됩니다. 아래는 문서, 대시보드, 후속 도구를 v1 인터페이스에 맞추는 분들을 위한 정리입니다.

## CLI 구조

v0 는 플래그 하나로 이루어진 평평한 구조였지만, v1 은 동사 계층을 도입해 각 기능이 자기 도움말 페이지를 갖습니다.

```
noir scan [PATHS...] [flags]   # 메인 엔드포인트 발견
noir list <techs|taggers|formats>
noir cache <info|clear|purge>
noir config <show|edit|init|path>
noir rules <list|update|path>
noir completion <zsh|bash|fish|elvish>
noir version [--verbose]
noir help [command]
```

기존 v0 의 단독 실행 플래그들은 대응하는 동사로 라우팅됩니다.

| v0 호출 | v1 호출 |
| --- | --- |
| `noir --list-techs` | `noir list techs` |
| `noir --list-taggers` | `noir list taggers` |
| `noir --build-info` | `noir version --verbose` |
| `noir --help-all` | `noir help` |
| `noir --generate-completion zsh` | `noir completion zsh` |

`noir -v` 와 `noir --version` 은 그대로 버전 문자열을 출력합니다.

## Deliver 플래그 이름 변경: PROBE / EXPORT

v0 `noir scan -h` 는 `DELIVER` 단일 섹션이었습니다. v1 은 이를 **PROBE** (발견된 엔드포인트에 실제 HTTP 요청을 보내는 능동 재전송) 와 **EXPORT** (카탈로그를 외부 저장소로 내보내기) 두 가지로 분리합니다. 이 분리로 `--probe-match` / `--probe-skip` / `--probe-header` 가 probe 에만 영향을 주고 stdout 의 JSON/SARIF 에는 영향을 주지 않는다는 점이 명확해집니다.

| v0 플래그 | v1 플래그 |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |
| `--send-es URL` | `--export-es URL` |

v0 이름들은 그대로 파싱됩니다. OptionParser 가 돌기 전에 v1 이름으로 재작성되므로 기존 CI 스크립트와 Dockerfile 은 손대지 않아도 됩니다. v1 의 `noir scan -h` 에는 옛 이름이 나오지 않으므로 신규 사용자는 정식 이름만 보게 됩니다.

v1 신규 추가:

* `--export-opensearch URL`: Elasticsearch 와 같은 HTTP 프로토콜을 사용
* `--export-webhook URL`: 엔드포인트 카탈로그를 단일 JSON 문서 (`{endpoints, endpoint_count, noir_version}`) 로 POST. Slack incoming webhook, Discord, Zapier/n8n, 사내 HTTP 리시버 모두 대상

## 설정 파일 (`~/.config/noir/config.yaml`)

v0 설정 파일의 YAML 키는 v0 플래그 이름과 같았습니다. v1 은 새 CLI 에 맞춥니다.

| v0 설정 키 | v1 설정 키 |
| --- | --- |
| `send_req` | `probe` |
| `send_proxy` | `probe_via` |
| `send_es` | `export_es` |
| `send_with_headers` | `probe_header` |
| `use_matchers` | `probe_match` |
| `use_filters` | `probe_skip` |

v0 설정 파일은 그대로 로드됩니다. `ConfigInitializer` 가 옵션 셋에 병합하기 전에 옛 키를 새 키로 옮깁니다. v0 설정 파일에 `noir config show` 를 실행하면 옮겨진 키 목록을 한 줄 메모로 알려주므로 무엇이 바뀌었는지 바로 알 수 있습니다.

한 파일에 두 이름이 같이 있으면 (마이그레이션 중간 상태) v1 키가 우선합니다.

## 동작 변화

플래그 이름은 그대로지만 스캔 결과가 달라지는 항목들입니다. 자세한 내용은 [v1.0.0 CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100) 를 참고하세요. 주요 항목:

* **기본 동시성** 이 v0 의 고정값 `"20"` 대신 호스트 CPU 수에 맞춰집니다. `--concurrency N` 이나 설정 파일의 `concurrency:` 가 있으면 그쪽이 우선합니다.
* **라우트 경로의 문자열 보간** (Python `f""`, Ruby/Crystal/Elixir `#{}`, PHP `$var`, Kotlin `${}`) 이 `{name}` 자리표시자로 보존됩니다. v0 는 보간 구간을 조용히 버리거나 언어 문법을 URL 에 그대로 노출했습니다. v1 은 일관된 템플릿을 만들고 자리표시자를 path 파라미터로 등록합니다.
* **`Any` / `All` 라우트** (Gin `r.Any`, axum `routing::any`, Echo `e.Any`, Fiber `app.All` 등) 가 비표준 `"ANY"` 메서드 하나 대신 실제 HTTP 메서드 (GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD, TRACE) 로 펼쳐집니다. SARIF, Postman 같은 후속 도구가 그대로 받아들일 수 있습니다. `QUERY` 는 의도적으로 제외되며, 라우트가 그 메서드를 명시적으로 선언한 경우에만 나옵니다.
* **stdout 출력** 이 터미널이 아니면 색상이 자동으로 꺼집니다. `ls` / `git` 관례와 같으며, `--no-color` 와 `NO_COLOR=1` 도 그대로 동작합니다.
* **`-f json` / `-f sarif`** 등이 엔드포인트가 0개일 때 빈 문자열 대신 유효한 빈 문서를 출력합니다. CI 파서가 빈 파일에서 실패하지 않습니다.
* **`--diff-path`** 가 비교 대상 스캔에서 `--probe` 와 `--export-*` 를 끕니다. v0 는 변경 없는 URL 을 양쪽에서 두 번 probe 했고, 옛 카탈로그까지 함께 내보냈습니다.
* **반복 플래그 누적** 이 `--exclude-path`, `--use-taggers`, `-t/--techs`, `--only-techs`, `--exclude-techs`, `--exclude-codes`, `--ai-native-tools-allowlist` 에서 동작합니다. v0 는 마지막 값만 남았습니다 (두 번째 `--exclude-techs flask` 가 첫 번째를 덮어씀). v1 은 매 호출을 목록에 이어 붙입니다.
* **Tagger / `--include` / `--ai-context` 이름** 이 대소문자를 구분하지 않습니다 (`--use-taggers Hunt` 가 `hunt` 와 동일).

## 명시적으로 깨진 것

* `--ollama URL` / `--ollama-model NAME`: 2024년부터 deprecated. `--ai-provider ollama [--ai-model NAME]` 사용. 둘 중 하나라도 쓰면 CLI 가 마이그레이션 힌트를 한 줄 출력합니다.

명시적으로 깨진 항목은 이것이 전부입니다.

## 업그레이드

설치 경로는 그대로:

```bash
brew upgrade noir
# 또는
docker pull ghcr.io/owasp-noir/noir:1.0.0
# 또는
gh release download v1.0.0 -R owasp-noir/noir
```

이 페이지에서 미처 다루지 않은 부분이 깨진다면 [GitHub Issues](https://github.com/owasp-noir/noir/issues) 에 올려주세요. v0 에서 v1 로 넘어올 때 조용히 깨지는 동작은 릴리스를 막는 버그로 다룹니다.
