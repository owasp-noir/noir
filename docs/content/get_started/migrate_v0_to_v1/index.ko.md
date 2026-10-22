+++
title = "v0에서 v1로 마이그레이션"
description = "Noir 0.x와 1.0 사이에 바뀐 것: 플래그, 설정 키, 동작, 그리고 v0 스크립트를 그대로 돌아가게 하는 호환 계층."
weight = 5
sort_by = "weight"

+++

{% mascot(mood="question") %}
v0 호출은 거의 다 v1에서도 그대로 돌아가. 이름이 바뀐 것, 동작이 달라진 것, 그리고 몇 안 되는 깨진 항목을 이 페이지에 한데 모아 뒀어.
{% end %}

## 요약

v1.0은 **호환성을 최우선**으로 했습니다. `noir -b ./app -P -f json` 같은 v0 호출은 자동으로 `scan` 서브커맨드로 넘어가고, 이름이 바뀐 플래그는 모두 옛 이름도 별칭으로 받습니다. 명시적으로 깨진 것은 `--ollama` / `--ollama-model`뿐입니다(2024년부터 지원 중단). 대신 `--ai-provider ollama [--ai-model NAME]`을 쓰세요.

업그레이드하고 계속 쓰기만 할 거라면 여기까지만 읽어도 됩니다. 나머지는 문서, 대시보드, 후속 도구를 v1에 맞춰 고치는 분을 위한 내용입니다.

## CLI 구조

v0는 플래그를 한 층에 모두 늘어놓은 구조였습니다. v1은 동사(서브커맨드) 계층을 두어 기능마다 도움말 페이지가 따로 있습니다.

```
noir scan [PATHS...] [flags]   # 핵심 기능인 엔드포인트 탐색
noir list <techs|taggers|formats>
noir cache <info|clear|purge>
noir config <show|edit|init|path>
noir rules <list|update|path>
noir completion <zsh|bash|fish|elvish>
noir version [--verbose]
noir help [command]
```

v1 이전의 단독 실행 플래그는 대응하는 동사로 넘어갑니다.

| v0 호출 | v1 호출 |
| --- | --- |
| `noir --list-techs` | `noir list techs` |
| `noir --list-taggers` | `noir list taggers` |
| `noir --build-info` | `noir version --verbose` |
| `noir --help-all` | `noir help` |
| `noir --generate-completion zsh` | `noir completion zsh` |

`noir -v`와 `noir --version`은 지금도 버전 문자열을 출력합니다.

## Deliver 플래그 이름 변경: PROBE / EXPORT

v0의 `noir scan -h`에는 `DELIVER` 섹션 하나만 있었습니다. v1은 이를 **PROBE**(발견한 엔드포인트에 실제 HTTP 요청을 다시 보냄)와 **EXPORT**(카탈로그를 외부 저장소로 보냄)로 나눕니다. 이렇게 나누면 `--probe-match` / `--probe-skip` / `--probe-header`가 프로브에만 영향을 주고 stdout의 JSON/SARIF에는 영향을 주지 않는다는 점이 분명해집니다.

| v0 플래그 | v1 플래그 |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |
| `--send-es URL` | `--export-es URL` |

v0 이름은 지금도 파싱됩니다. 옵션 파서가 돌기 전에 v1 이름으로 바뀌므로 기존 CI 스크립트와 Dockerfile은 고칠 필요가 없습니다. `noir scan -h`에는 옛 이름이 나오지 않아서 새 사용자는 v1 이름만 보게 됩니다.

v1에 새로 추가된 플래그:

* `--export-opensearch URL`: Elasticsearch와 같은 HTTP 프로토콜을 씁니다.
* `--export-webhook URL`: 엔드포인트 카탈로그를 JSON 문서 하나(`{endpoints, endpoint_count, noir_version}`)로 아무 HTTP 수신 측에 POST합니다(Slack incoming webhook, Discord, Zapier/n8n, 사내 엔드포인트 등).

## 통합된 플래그: `--include`와 `--pvalue`

v0에는 보강 항목마다, 파라미터 타입마다 플래그가 따로 있었습니다. v1은 각 묶음을 목록이나 `TYPE=VAL` 쌍을 받는 플래그 하나로 합쳤습니다. 옛 이름도 별칭으로 계속 동작합니다.

| v0 플래그 | v1 플래그 |
| --- | --- |
| `--include-path` | `--include path` |
| `--include-techs` | `--include techs` |
| `--include-callee` | `--include callee` |
| `--set-pvalue VAL` | `--pvalue VAL` (또는 `--pvalue any=VAL`) |
| `--set-pvalue-header VAL` | `--pvalue header=VAL` |
| `--set-pvalue-cookie VAL` | `--pvalue cookie=VAL` |
| `--set-pvalue-query VAL` | `--pvalue query=VAL` |
| `--set-pvalue-form VAL` | `--pvalue form=VAL` |
| `--set-pvalue-json VAL` | `--pvalue json=VAL` |
| `--set-pvalue-path VAL` | `--pvalue path=VAL` |

보강 항목은 플래그 하나에 묶고(`--include path,techs`), 여러 타입에 값을 넣을 때는 `--pvalue`를 반복하세요.

## 설정 파일 (`~/.config/noir/config.yaml`)

v0 설정 파일은 CLI 플래그와 같은 평평한 구조라서 YAML 키도 v0 플래그 이름을 따랐습니다. v1은 새 CLI에 맞춥니다.

| v0 설정 키 | v1 설정 키 |
| --- | --- |
| `send_req` | `probe` |
| `send_proxy` | `probe_via` |
| `send_es` | `export_es` |
| `send_with_headers` | `probe_header` |
| `use_matchers` | `probe_match` |
| `use_filters` | `probe_skip` |

v0 설정 파일은 그대로 읽힙니다. Noir가 파일을 옵션에 합치기 전에 옛 키 이름을 바꿉니다. v0 설정 파일로 `noir config show`를 실행하면 v0 키와 그에 대응하는 v1 이름을 메모로 알려 줍니다.

한 파일에 두 이름이 함께 있으면(마이그레이션 중간 상태) v1 키가 우선합니다.

## 동작 변화

플래그 이름은 그대로지만 스캔 결과가 달라지는 항목입니다. 자세한 내용은 [v1.0.0 CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100)에 있습니다. 주요 항목:

* **기본 동시성**이 v0의 고정값 `"20"` 대신 호스트 CPU 수를 따르며 4–32 범위로 제한됩니다. `--concurrency N`, 설정 파일의 `concurrency:`, `NOIR_CONCURRENCY` 환경 변수를 지정하면 그 값이 우선합니다.
* **라우트 경로의 문자열 보간**(Python `f""`, Ruby/Crystal/Elixir `#{}`, PHP `$var`, Kotlin `${}`)이 `{name}` 자리표시자로 남습니다. v0는 보간 구간을 말없이 버리거나 언어 문법을 URL에 그대로 흘렸습니다. v1은 일관된 템플릿을 만들고 자리표시자를 path 파라미터로 등록합니다.
* **`Any` / `All` 메서드**(Gin `r.Any`, axum `routing::any`, Echo `e.Any`, Fiber `app.All` 등)가 실제 HTTP 메서드(GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD)로 펼쳐집니다. v0는 SARIF나 Postman이 받지 못하는 비 HTTP `"ANY"` 메서드를 냈습니다. `QUERY`는 일부러 이 목록에서 뺐고, 라우트가 그 메서드를 직접 선언한 경우에만 나옵니다.
* **stdout 출력**은 stdout이 터미널이 아니면 색상이 자동으로 꺼집니다. `ls` / `git`과 같은 관례입니다. `--no-color`와 `NO_COLOR=1`은 지금도 색상을 강제로 끕니다.
* **`-f json` / `-f sarif`** 등은 엔드포인트가 0개여도 아무것도 쓰지 않는 대신 유효한 빈 문서를 출력합니다. CI 파서가 빈 파일 때문에 실패하지 않습니다.
* **`--diff-path`** 옵션은 비교 대상 쪽 스캔에서 `--probe`와 `--export-*`를 끕니다. 전에는 바뀌지 않은 URL을 양쪽에서 한 번씩 두 번 프로브했고, 옛 카탈로그도 새 카탈로그와 함께 내보냈습니다.
* **반복 플래그 누적**: `--exclude-path`, `--use-taggers`, `-t/--techs`, `--only-techs`, `--exclude-techs`, `--exclude-codes`, `--ai-native-tools-allowlist`. v0는 마지막 값만 남았습니다(두 번째 `--exclude-techs flask`가 첫 번째를 덮어씀). v1은 쓸 때마다 목록에 더합니다.
* **태거 / `--include` / `--ai-context` 이름**은 대소문자를 가리지 않습니다(`--use-taggers Hunt`는 `hunt`와 같음).

## 명시적으로 깨진 것

* `--ollama URL` / `--ollama-model NAME`: 둘 다 2024년부터 지원 중단 상태였습니다. 대신 `--ai-provider ollama [--ai-model NAME]`을 쓰세요. 둘 중 하나라도 넘기면 Noir가 대체 명령을 보여 주는 오류를 내고 멈춥니다.

깨진 항목은 이것이 전부입니다.

## 업그레이드

설치 방법은 그대로입니다.

```bash
brew upgrade noir
# 또는
docker pull ghcr.io/owasp-noir/noir:latest
# 또는 (최신 릴리즈의 Linux x86_64 바이너리)
gh release download -R owasp-noir/noir --pattern 'noir-v*-linux-x86_64'
```

이 페이지에서 예상하지 못한 부분이 깨진다면 [GitHub Issues](https://github.com/owasp-noir/noir/issues)에 올려 주세요. v0에서 v1로 넘어오며 말없이 깨지는 동작은 릴리즈를 막는 버그로 다룹니다.
