+++
title = "Step 3: 첫 번째 스캔"
description = "Noir로 첫 번째 스캔을 실행하고 결과를 살펴봅니다."
weight = 3
sort_by = "weight"

+++

> **목표**: 코드베이스를 스캔하고 결과를 이해합니다.

## 1. 스캔 실행

프로젝트 디렉토리를 지정하세요:

```bash
noir -b /path/to/your/app
```

또는 현재 디렉토리를 스캔:

```bash
noir -b .
```

![](./running.png)

Noir가 자동으로 사용된 기술을 탐지하고 엔드포인트를 추출합니다.

## 2. 탐지된 기술 확인

프로젝트에서 Noir가 발견한 기술을 확인하세요:

```bash
noir -b . --include-techs
```

지원되는 기술의 전체 목록을 보려면:

```bash
noir --list-techs
```

## 3. 다양한 출력 형식 사용

기본 출력은 표 형식입니다. 다른 형식으로 전환해 보세요:

```bash
# 스크립팅과 자동화를 위한 JSON
noir -b . -f json

# 사람이 읽기 쉬운 YAML
noir -b . -f yaml

# API 문서를 위한 OpenAPI 명세
noir -b . -f oas3

# 엔드포인트를 바로 테스트할 수 있는 cURL 명령
noir -b . -f curl -u https://your-target.com
```

## 4. 결과를 파일로 저장

```bash
noir -b . -f json -o results.json
```

## 5. 출력 커스터마이즈

엔드포인트가 발견된 소스 파일 경로를 포함:

```bash
noir -b . --include-path
```

옵션 조합:

```bash
noir -b . --include-path --include-techs -f json -o results.json
```

## 6. 기술별 필터링

프로젝트에 여러 프레임워크가 있다면 스캔 범위를 좁힐 수 있습니다:

```bash
# 특정 프레임워크만 스캔
noir -b . --techs rails,django

# 불필요한 프레임워크 건너뛰기
noir -b . --exclude-techs express
```

## 주요 플래그

| 플래그 | 설명 |
|---|---|
| `-b <경로>` | 스캔할 기본 디렉토리 |
| `-f <형식>` | 출력 형식 (json, yaml, oas3, curl 등) |
| `-o <파일>` | 출력을 파일로 저장 |
| `-u <URL>` | cURL/HTTPie 출력의 기본 URL 설정 |
| `--include-path` | 소스 파일 경로 표시 |
| `--include-techs` | 탐지된 기술 표시 |
| `--techs` | 이 기술만 스캔 |
| `--exclude-techs` | 이 기술 건너뛰기 |
| `--verbose` | 상세 로그 출력 |
| `--no-log` | 모든 로그 메시지 억제 |
| `--help` | 전체 도움말 표시 |

---

시작하기 가이드를 완료했습니다! 다음으로 살펴볼 내용:

- **[설정](@/usage/configurations/configuration_file/index.md)** — 설정 파일로 플래그 반복 입력을 줄이기
- **[출력 형식](@/usage/output_formats/_index.md)** — 사용 가능한 모든 출력 형식 살펴보기
- **[패시브 스캔](@/usage/passive_scan/_index.md)** — 패시브 보안 스캔으로 취약점 찾기
- **[AI 기반 분석](@/get_started/ai_power/index.md)** — AI로 미지원 프레임워크의 엔드포인트 탐지
