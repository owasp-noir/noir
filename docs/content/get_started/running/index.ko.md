+++
title = "첫 번째 스캔"
description = "Noir로 첫 번째 스캔을 실행하고 결과를 살펴봅니다."
weight = 3
sort_by = "weight"
prev_page_path = "/get_started/installation/"
prev_page_label = "Noir 설치"

+++

{% mascot(mood="walk") %}
Noir가 설치됐으니 바로 써보자! 프로젝트를 분석하고, 무엇을 찾았는지 확인하고, 출력을 다루는 방법을 배워보자.
{% end %}

이 페이지에서는 첫 스캔을 처음부터 끝까지 따라갑니다 — 프로젝트를 지정하고, 결과를 읽고, 워크플로우에 맞게 출력을 다듬는 과정입니다. 각 단계는 앞 단계에 이어지므로 처음에는 순서대로 따라가는 것을 권장합니다.

## 스캔 실행

프로젝트 디렉토리를 지정하여 스캔합니다:

```bash
noir scan /path/to/your/app
```

프로젝트 안에 이미 있다면:

```bash
noir scan .
```

![](./running.png)

Noir가 소스 파일을 읽고, 사용 중인 프레임워크를 탐지하고, 발견한 모든 엔드포인트를 출력합니다. 메서드, 경로, 파라미터, 헤더, 쿠키까지 함께요.

> **v0 호환:** `noir -b ./app` 같은 v0 형식도 변경 없이 그대로
> 동작합니다. 라우터가 플래그만 있는 호출을 자동으로 `scan` 으로
> 보냅니다.

## 탐지된 기술 확인

Noir가 어떤 기술을 감지했는지 궁금하다면 `--include techs`를 추가하세요:

```bash
noir scan . --include techs
```

Noir가 분석할 수 있는 모든 기술을 보려면:

```bash
noir list techs
```

목록에 없는 프레임워크라면 [AI 기반 분석](@/get_started/ai_power/index.md)으로 엔드포인트를 탐지할 수 있습니다.

## 다양한 출력 형식 사용

기본 출력은 사람이 읽기 좋은 표 형식입니다. 워크플로에 따라 다른 형식이 필요할 수 있습니다.

```bash
# 스크립트와 파이프라인에 적합한 JSON
noir scan . -f json

# 사람이 읽기 좋고 설정 파일에 어울리는 YAML
noir scan . -f yaml

# API 문서 생성이나 도구 연동에 쓰는 OpenAPI 명세
noir scan . -f oas3

# 대상에 바로 실행 가능한 cURL 명령
noir scan . -f curl -u https://your-target.com
```

사용 가능한 모든 형식은 `noir list formats` 또는 [출력 형식](@/usage/output_formats/_index.md) 섹션을 참조하세요.

## 결과를 파일로 저장

터미널 출력 대신 `-o`로 파일에 기록할 수 있습니다:

```bash
noir scan . -f json -o results.json
```

스캔 간 결과 비교, CI 파이프라인 연동, 팀과의 공유에 유용합니다.

## 엔드포인트를 소스까지 추적

엔드포인트가 정확히 어디서 정의되어 있는지 알고 싶다면 `--include path` 를 추가하세요.

```bash
noir scan . --include path
```

여러 항목을 한 플래그에 묶을 수 있습니다.

```bash
noir scan . --include path,techs -f json -o results.json
```

## 스캔 범위 좁히기

대규모 모노레포에는 여러 프레임워크가 섞여 있을 수 있습니다. 필요한 것만 스캔합니다.

```bash
# Rails 와 Django 디텍터만 실행 (나머지는 건너뜀)
noir scan . --only-techs rails,django

# 디텍터는 실행하지 않고 결과에 기술 태그만 강제로 추가
noir scan . --techs rails,django

# Express 만 제외하고 나머지 전부 스캔
noir scan . --exclude-techs express

# 모노레포에서 glob 패턴으로 파일 제외 (쉼표로 구분)
noir scan . --exclude-path "*_test.go,vendor/*,**/node_modules/**"
```

`--only-techs` 와 `--techs` 는 비슷해 보이지만 다릅니다.
`--only-techs` 는 디텍터 목록을 필터링해서 지정한 항목만 탐지를
실행하고(스캔 속도 향상), `--techs` 는 탐지를 건너뛰고 결과에 기술
태그만 강제로 추가합니다(스택을 이미 알고 있을 때 사용).

## 출력 보강하기

`--include` 는 plain 출력에 엔드포인트별 부가 정보를 더하고,
`--ai-context` 는 리뷰용 컨텍스트를 첨부합니다.

```bash
# 라우트 본문 안의 1-hop 핸들러 callee 첨부
noir scan . --include callee

# AI 리뷰용 컨텍스트 첨부 (guards, callees, sinks, validators, signals)
noir scan . --ai-context

# AI 컨텍스트 범위 좁히기
noir scan . --ai-context guards,sinks
```

데이터 모양과 프레임워크별 지원은 [Callee 커버리지](@/usage/supported/callee_coverage/index.md)와 [AI 컨텍스트](@/usage/supported/ai_context_coverage/index.md)를 참고하세요.

## 주요 플래그 정리

| 플래그                | 역할 |
|----------------------|---|
| positional 경로       | 스캔할 디렉토리(들). 예: `noir scan ./api ./worker` |
| `-b <경로>`           | positional 과 동치, v0 호환 |
| `-f <형식>`           | 출력 형식 (json, yaml, oas3, curl 등) |
| `-o <파일>`           | 출력을 파일로 저장 |
| `-u <URL>`            | cURL/HTTPie 출력의 기본 URL |
| `--include LIST`      | plain 출력에 `path`, `techs`, `callee` 추가 (쉼표 구분) |
| `--ai-context [LIST]` | AI 리뷰 컨텍스트 첨부 (`guards`, `sinks`, `validators`, `signals`, `callee`) |
| `--pvalue TYPE=VAL`   | 출력에 파라미터 값 채우기 (TYPE: any / header / cookie / query / form / json / path) |
| `--only-techs`        | 이 디텍터만 실행 (나머지 건너뜀) |
| `--techs`             | 디텍터는 건너뛰고 결과에 기술 태그만 강제 추가 |
| `--exclude-techs`     | 이 프레임워크 건너뛰기 |
| `--exclude-path`      | 쉼표 구분 glob 패턴에 매치되는 파일 제외 |
| `--status-codes`      | 각 엔드포인트를 호출해 응답 HTTP 상태 코드를 첨부 |
| `--exclude-codes`     | 응답 상태가 매치되는 엔드포인트 제외 (쉼표 구분, `--status-codes` 와 함께) |
| `--config-file <경로>`| YAML 설정 파일에서 기본 옵션 로드 |
| `--concurrency <N>`   | 워커 수 (기본값: CPU 코어 수) |
| `--cache-disable`     | 이번 실행에 한해 LLM 응답 캐시 비활성화 |
| `--cache-clear`       | 실행 전에 LLM 응답 캐시 초기화 |
| `--verbose`           | 상세 로깅 |
| `--no-log`            | 모든 로그 억제 |
| `--no-color`          | plain 출력의 ANSI 색상 비활성화 |

빌드 세부 정보(Crystal / LLVM / 타깃)는 `noir version --verbose` 로 확인할 수 있습니다. `noir help` 는 최상위 개요를, `noir help <command>` 는 해당 명령어의 전체 플래그 목록을 보여줍니다.

---

시작하기 가이드를 완료했습니다! 다음으로 살펴볼 내용:

- **[CLI 명령어](@/usage/cli_commands/_index.md)**: v1 서브커맨드(scan, list, cache, config, rules 등) 전체 레퍼런스
- **[설정](@/usage/configurations/configuration_file/index.md)**: 매번 플래그를 반복하지 않도록 기본 옵션 설정
- **[출력 형식](@/usage/output_formats/_index.md)**: 모든 출력 형식 자세히 알아보기
- **[패시브 스캔](@/usage/passive_scan/_index.md)**: 하드코딩된 비밀키, 잘못된 설정 등 보안 이슈 스캔
- **[AI 기반 분석](@/get_started/ai_power/index.md)**: AI로 미지원 프레임워크의 엔드포인트 탐지
