+++
title = "v0 에서 v1 로 마이그레이션"
description = "Noir 0.x 와 1.0 사이의 변경점 — flag, config key, behavior, 그리고 v0 스크립트를 그대로 굴리게 해주는 호환 shim 모음."
weight = 5
sort_by = "weight"

+++

{% mascot(mood="think") %}
거의 모든 v0 invocation 은 v1 에서 그대로 굴러갑니다. 이 페이지는 rename 과 behavior 변화, 명시적으로 깨진 항목 몇 가지를 한 곳에서 찾기 위한 정리입니다.
{% end %}

이 가이드는 훑어보기 좋게 구성했습니다. 아래 TL;DR 부터 보고, 실제로 스크립트나 대시보드가 건드리는 CLI·flag·출력 섹션만 골라서 보면 됩니다.

## TL;DR

v1.0 은 **compatibility-first** 입니다. `noir -b ./app -P -f json` 같은 v0 호출은 자동으로 `scan` 서브커맨드로 라우팅되고, rename 된 모든 flag 는 옛 이름을 silent alias 로 유지합니다. 명시적으로 깨진 것은 `--ollama` / `--ollama-model` 뿐 (2024년부터 deprecated). 대체는 `--ai-provider ollama [--ai-model NAME]` 입니다.

업그레이드만 하고 계속 쓸 거라면 여기까지만 읽어도 됩니다. 아래는 문서, 대시보드, downstream 도구를 v1 표면에 맞추는 분들을 위한 정리입니다.

## CLI structure

v0 는 평평한 flag 셋이었는데, v1 은 동사 layer 를 도입해서 각 기능이 자기 help 페이지를 갖습니다.

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

기존 v0 의 terminal flag 들은 등가 verb 로 라우팅됩니다.

| v0 호출 | v1 호출 |
| --- | --- |
| `noir --list-techs` | `noir list techs` |
| `noir --list-taggers` | `noir list taggers` |
| `noir --build-info` | `noir version --verbose` |
| `noir --help-all` | `noir help` |
| `noir --generate-completion zsh` | `noir completion zsh` |

`noir -v` 와 `noir --version` 은 그대로 version 문자열 출력입니다.

## Deliver flag rename — PROBE / EXPORT

v0 `noir scan -h` 는 `DELIVER` 단일 섹션이었습니다. v1 은 이를 **PROBE** (발견된 endpoint 로 실제 HTTP 요청을 쏘는 active replay) 와 **EXPORT** (catalog 을 외부 저장소로 ship) 두 가지로 분리합니다. 이 분리로 `--probe-match` / `--probe-skip` / `--probe-header` 가 probe 만 영향주고 stdout 의 JSON/SARIF 에는 영향 안 준다는 점이 명확해집니다.

| v0 flag | v1 flag |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |
| `--send-es URL` | `--export-es URL` |

v0 이름들은 그대로 파싱됩니다. OptionParser 가 돌기 전에 v1 spelling 으로 재작성되므로 기존 CI 스크립트와 Dockerfile 은 손 안 대도 됩니다. v1 의 `noir scan -h` 에는 legacy 이름이 안 나와서 신규 사용자는 canonical 표면만 봅니다.

v1 신규 추가:

* `--export-opensearch URL` — Elasticsearch 와 같은 HTTP 프로토콜이라 같은 코드 경로 사용
* `--export-webhook URL` — endpoint catalog 을 단일 JSON 문서 (`{endpoints, endpoint_count, noir_version}`) 로 POST. Slack incoming webhook, Discord, Zapier/n8n, 내부 임의 HTTP 리시버 모두 대상

## Config file (`~/.config/noir/config.yaml`)

v0 config 의 YAML key 는 v0 flag 이름과 같았습니다. v1 은 새 CLI 에 맞춥니다.

| v0 config key | v1 config key |
| --- | --- |
| `send_req` | `probe` |
| `send_proxy` | `probe_via` |
| `send_es` | `export_es` |
| `send_with_headers` | `probe_header` |
| `use_matchers` | `probe_match` |
| `use_filters` | `probe_skip` |

v0 config 파일은 그대로 load 됩니다. `ConfigInitializer` 가 옵션 셋에 머지하기 전에 legacy key 마이그레이션을 돌립니다. v0 config 에 `noir config show` 를 실행하면 마이그레이트된 key 들을 stderr 에 한 줄 NOTE 로 알려주므로 무엇이 바뀌었는지 바로 알 수 있습니다.

한 파일에 두 spelling 이 같이 있으면 (마이그레이션 중간 상태) v1 key 가 우선입니다.

## Behavior 변화

Flag 이름은 그대로지만 scan 결과가 달라지는 항목들입니다. 자세한 내용은 [v1.0.0 CHANGELOG](https://github.com/owasp-noir/noir/blob/main/CHANGELOG.md#v100) 참고. 하이라이트:

* **Default concurrency** 가 v0 의 고정 `"20"` 대신 host CPU 수에 비례합니다. `--concurrency N` 이나 config 의 `concurrency:` 가 있으면 그쪽이 우선.
* **Route path 의 string interpolation** (Python `f""`, Ruby/Crystal/Elixir `#{}`, PHP `$var`, Kotlin `${}`) 이 `{name}` placeholder 로 보존됩니다. v0 는 interpolation segment 를 silently drop 하거나 언어 syntax 를 URL 에 leak 했습니다. v1 은 일관된 template 을 만들고 placeholder 를 path parameter 로 등록합니다.
* **`Any` / `All` verb** (Gin `r.Any`, axum `routing::any`, Echo `e.Any`, Fiber `app.All` 등) 가 단일 비표준 `"ANY"` verb 대신 7개 표준 HTTP method 로 fan out 됩니다. SARIF, Postman 등 downstream 가 ingest 가능.
* **Stdout 출력** 이 터미널이 아닐 때 자동으로 컬러 비활성. `ls` / `git` 컨벤션과 일치. `--no-color` 와 `NO_COLOR=1` 도 그대로 동작.
* **`-f json` / `-f sarif`** 등이 endpoint 0 일 때 빈 문자열 대신 valid empty document 출력. CI 파서가 빈 파일에서 실패하지 않음.
* **`--diff-path`** 가 비교 측 scan 에서 `--probe` 와 `--export-*` 를 끕니다. v0 는 변경 없는 URL 을 양쪽에서 두 번 probe 했고, 옛 catalog 도 ES 로 push 했습니다.
* **Repeat-flag 누적** 이 `--exclude-path`, `--use-taggers`, `-t/--techs`, `--only-techs`, `--exclude-techs`, `--exclude-codes`, `--ai-native-tools-allowlist` 에서 동작합니다. v0 는 last-write-wins 였습니다 (두 번째 `--exclude-techs flask` 가 첫 번째를 덮어씀). v1 은 concatenate 해서 매 호출이 리스트에 추가됩니다.
* **Tagger / `--include` / `--ai-context` 이름** 이 case-insensitive (`--use-taggers Hunt` 가 `hunt` 와 동일).

## 명시적으로 깨진 것

* `--ollama URL` / `--ollama-model NAME` — 2024년부터 deprecated. `--ai-provider ollama [--ai-model NAME]` 사용. 둘 중 하나라도 쓰면 CLI 가 마이그레이션 힌트를 한 줄 출력합니다.

breaking surface 는 이게 전부입니다.

## Upgrade

설치 경로는 그대로:

```bash
brew upgrade noir
# 또는
docker pull ghcr.io/owasp-noir/noir:1.0.0
# 또는
gh release download v1.0.0 -R owasp-noir/noir
```

이 페이지에서 미처 다루지 않은 부분에서 깨지면 [GitHub Issues](https://github.com/owasp-noir/noir/issues) 에 올려주세요. v0→v1 silent breakage 는 release-blocker 입니다.
