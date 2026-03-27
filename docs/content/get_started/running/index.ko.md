+++
title = "첫 번째 스캔"
description = "Noir로 첫 번째 스캔을 실행하고 결과를 살펴봅니다."
weight = 3
sort_by = "weight"

+++

Noir가 설치되었으니 실제 프로젝트를 스캔해 봅시다. 코드베이스를 분석하고, 무엇을 찾았는지 확인하고, 출력을 다루는 방법을 배웁니다.

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

Noir가 소스 파일을 읽고, 사용 중인 프레임워크를 탐지하고, 발견한 모든 엔드포인트를 출력합니다 — 메서드, 경로, 파라미터, 헤더, 쿠키를 포함해서.

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
# Rails와 Django 엔드포인트만 스캔
noir -b . --techs rails,django

# Express를 제외한 모든 것 스캔
noir -b . --exclude-techs express
```

## 주요 플래그 정리

| 플래그 | 역할 |
|---|---|
| `-b <경로>` | 스캔할 디렉토리 |
| `-f <형식>` | 출력 형식 (json, yaml, oas3, curl 등) |
| `-o <파일>` | 출력을 파일로 저장 |
| `-u <URL>` | cURL/HTTPie 출력의 기본 URL |
| `--include-path` | 소스 파일 위치 표시 |
| `--include-techs` | 탐지된 기술 표시 |
| `--techs` | 이 프레임워크만 스캔 |
| `--exclude-techs` | 이 프레임워크 건너뛰기 |
| `--verbose` | 상세 로깅 |
| `--no-log` | 모든 로그 억제 |
| `--help` | 전체 도움말 |

---

시작하기 가이드를 완료했습니다! 다음으로 살펴볼 내용:

- **[설정](@/usage/configurations/configuration_file/index.md)** — 매번 플래그를 반복하지 않도록 기본 옵션 설정
- **[출력 형식](@/usage/output_formats/_index.md)** — 모든 출력 형식 자세히 알아보기
- **[패시브 스캔](@/usage/passive_scan/_index.md)** — 하드코딩된 비밀키, 잘못된 설정 등 보안 이슈 스캔
- **[AI 기반 분석](@/get_started/ai_power/index.md)** — AI로 미지원 프레임워크의 엔드포인트 탐지
