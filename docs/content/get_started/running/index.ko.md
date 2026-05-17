+++
title = "첫 번째 스캔"
description = "Noir로 첫 번째 스캔을 실행하고 결과를 살펴봅니다."
weight = 3
sort_by = "weight"

+++

{% mascot(mood="walk") %}
Noir가 설치됐으니 바로 써보자! 프로젝트를 분석하고, 무엇을 찾았는지 확인하고, 출력을 다루는 방법을 배워보자.
{% end %}

## 스캔 실행

프로젝트 디렉토리를 지정하여 스캔합니다:

```bash
noir -b /path/to/your/app
```

프로젝트 안에 이미 있다면:

```bash
noir -b .
```

![](./running.png)

Noir가 소스 파일을 읽고, 사용 중인 프레임워크를 탐지하고, 발견한 모든 엔드포인트를 출력합니다. 메서드, 경로, 파라미터, 헤더, 쿠키까지 함께요.

## 탐지된 기술 확인

Noir가 어떤 기술을 감지했는지 궁금하다면 `--include-techs`를 추가하세요:

```bash
noir -b . --include-techs
```

Noir가 분석할 수 있는 모든 기술을 보려면:

```bash
noir --list-techs
```

목록에 없는 프레임워크라면 [AI 기반 분석](@/get_started/ai_power/index.md)으로 엔드포인트를 탐지할 수 있습니다.

## 다양한 출력 형식 사용

기본 출력은 사람이 읽기 쉬운 표 형식입니다. 워크플로에 따라 다른 형식이 필요할 수 있습니다:

```bash
# 스크립팅과 파이프라인을 위한 JSON
noir -b . -f json

# 읽기 쉽고 설정 친화적인 YAML
noir -b . -f yaml

# API 문서 생성이나 도구 연동에 유용한 OpenAPI 명세
noir -b . -f oas3

# 라이브 타겟에 바로 실행할 수 있는 cURL 명령
noir -b . -f curl -u https://your-target.com
```

사용 가능한 모든 형식은 [출력 형식](@/usage/output_formats/_index.md) 섹션을 참조하세요.

## 결과를 파일로 저장

터미널 출력 대신 `-o`로 파일에 기록할 수 있습니다:

```bash
noir -b . -f json -o results.json
```

스캔 간 결과 비교, CI 파이프라인 연동, 팀과의 공유에 유용합니다.

## 엔드포인트를 소스까지 추적

엔드포인트가 정확히 어디서 정의되었는지 알고 싶다면 `--include-path`를 추가하세요:

```bash
noir -b . --include-path
```

다른 옵션과 조합하면 전체 그림을 볼 수 있습니다:

```bash
noir -b . --include-path --include-techs -f json -o results.json
```

## 스캔 범위 좁히기

대규모 모노레포에는 여러 프레임워크가 포함될 수 있습니다. 필요한 것만 스캔할 수 있습니다:

```bash
# Rails와 Django 디텍터만 실행 (나머지는 건너뜀)
noir -b . --only-techs rails,django

# 디텍터는 돌리지 않고 결과에 강제로 태그만 부여
noir -b . --techs rails,django

# Express를 제외한 모든 것 스캔
noir -b . --exclude-techs express

# glob으로 파일 단위 제외 (모노레포에서 유용 — 쉼표 구분)
noir -b . --exclude-path "*_test.go,vendor/*,**/node_modules/**"
```

`--only-techs`와 `--techs`는 비슷해 보이지만 다릅니다: `--only-techs`는 디텍터 리스트를 필터링해서 그 항목만 실제로 탐지를 수행(스캔 속도 향상)하고, `--techs`는 탐지 없이 결과에 기술 태그만 강제로 추가(스택을 이미 알고 있을 때 사용)합니다.

## 출력 보강하기

탐지 파이프라인은 그대로 둔 채 엔드포인트에 부가 컨텍스트만 덧붙이는 플래그들:

```bash
# 라우트 본문 안의 1-hop 핸들러 callee를 첨부
noir -b . --include-callee

# AI 리뷰에 바로 쓸 컨텍스트 첨부 (guards, callees, sinks, validators, signals)
noir -b . --ai-context
```

데이터 모양과 프레임워크별 지원은 [Callee 커버리지](@/usage/supported/callee_coverage/index.md)와 [AI 컨텍스트](@/usage/supported/ai_context_coverage/index.md)를 참고하세요.

## 주요 플래그 정리

| 플래그 | 역할 |
|---|---|
| `-b <경로>` | 스캔할 디렉토리 |
| `-f <형식>` | 출력 형식 (json, yaml, oas3, curl 등) |
| `-o <파일>` | 출력을 파일로 저장 |
| `-u <URL>` | cURL/HTTPie 출력의 기본 URL |
| `--include-path` | 소스 파일 위치 표시 |
| `--include-techs` | 탐지된 기술 표시 |
| `--include-callee` | 1-hop 핸들러 callee 첨부 |
| `--ai-context` | AI 리뷰용 guard/sink/validator/signal 첨부 |
| `--set-pvalue` / `--set-pvalue-<type>` | 출력에 파라미터 값을 채워 넣음 ([HTTP 클라이언트 명령어](@/usage/output_formats/curl/index.md) 참고) |
| `--only-techs` | 이 디텍터만 실행 (나머지 건너뜀) |
| `--techs` | 디텍터는 건너뛰고 결과에 기술 태그만 강제 추가 |
| `--exclude-techs` | 이 프레임워크 건너뛰기 |
| `--exclude-path` | 쉼표 구분 glob 패턴에 매치되는 파일 제외 |
| `--status-codes` | 각 엔드포인트를 호출해 응답 HTTP 상태 코드를 첨부 |
| `--exclude-codes` | 응답 상태가 매치되는 엔드포인트 제외 (쉼표 구분, `--status-codes` 와 함께) |
| `--config-file <경로>` | YAML 설정 파일에서 기본 옵션 로드 |
| `--concurrency <N>` | 워커 수 (기본값: CPU 코어 수) |
| `--cache-disable` | 이번 실행에 한해 LLM 응답 캐시 비활성화 |
| `--cache-clear` | 실행 전에 LLM 응답 캐시 초기화 |
| `--verbose` | 상세 로깅 |
| `--no-log` | 모든 로그 억제 |
| `--no-color` | plain 출력의 ANSI 색상 비활성화 |
| `--build-info` | noir / Crystal / LLVM 버전과 타깃 트리플 출력 |
| `--help` | 전체 도움말 |
| `--help-all` | 예제 및 환경 변수까지 포함된 전체 도움말 |

---

시작하기 가이드를 완료했습니다! 다음으로 살펴볼 내용:

- **[설정](@/usage/configurations/configuration_file/index.md)**: 매번 플래그를 반복하지 않도록 기본 옵션 설정
- **[출력 형식](@/usage/output_formats/_index.md)**: 모든 출력 형식 자세히 알아보기
- **[패시브 스캔](@/usage/passive_scan/_index.md)**: 하드코딩된 비밀키, 잘못된 설정 등 보안 이슈 스캔
- **[AI 기반 분석](@/get_started/ai_power/index.md)**: AI로 미지원 프레임워크의 엔드포인트 탐지
