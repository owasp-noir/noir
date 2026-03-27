+++
title = "출력 형식"
description = "Noir는 스캔 결과를 최대한 활용할 수 있도록 광범위한 출력 형식을 지원합니다. 이 섹션은 JSON, YAML, TOML, OpenAPI 명세(OAS) 등을 포함한 사용 가능한 형식에 대한 개요를 제공합니다."
weight = 2
sort_by = "weight"

+++

Noir는 모든 워크플로에 적합한 다재다능한 도구로 구축되었습니다. 이러한 유연성의 핵심 부분은 스캔 결과를 다양한 형식으로 출력할 수 있는 능력입니다. 자동화를 위한 기계 판독 가능한 형식이 필요하든 수동 검토를 위한 사람이 읽기 쉬운 형식이 필요하든, Noir가 모든 것을 제공합니다.

## 형식 선택 가이드

| 사용 사례 | 추천 형식 | 플래그 |
|---|---|---|
| 스크립트/도구 연동 | [JSON](json/) | `-f json` |
| CI/CD 보안 리포팅 | [SARIF](sarif/) | `-f sarif` |
| API 문서 생성 | [OpenAPI](openapi/) | `-f oas3` |
| 빠른 엔드포인트 테스트 | [cURL](curl/) / HTTPie / PowerShell | `-f curl` |
| 사람이 읽기 쉬운 검토 | [YAML](yaml/) | `-f yaml` |
| 설정 스타일 출력 | [기타](more/) (TOML) | `-f toml` |
| Postman으로 가져오기 | [기타](more/) (Postman Collection) | `-f postman` |
| 시각적 보고서 공유 | [HTML](html/) | `-f html` |
| API 구조 시각화 | [Mermaid](mermaid/) | `-f mermaid` |
| URL이나 파라미터만 추출 | [기타](more/) (필터) | `-f only-url` |

## 사용 가능한 형식

*   **[HTTP 클라이언트 명령](curl/)**: 엔드포인트 테스트를 위한 실행 가능한 cURL, HTTPie, PowerShell 명령을 생성합니다.
*   **[JSON 및 JSONL](json/)**: 다른 도구 및 스크립트와 통합하기에 완벽한 널리 사용되는 형식입니다.
*   **[YAML](yaml/)**: 구성 파일 및 수동 검사에 적합한 사람이 읽기 쉬운 형식입니다.
*   **[OpenAPI 명세(OAS)](openapi/)**: 코드에서 OpenAPI 문서를 생성하여 API 문서를 쉽게 만들거나 보안 테스트를 설정합니다.
*   **[SARIF](sarif/)**: CI/CD 플랫폼과 네이티브 통합이 가능한 보안 도구 출력용 업계 표준 형식입니다.
*   **[HTML 보고서](html/)**: 스캔 결과의 포괄적인 시각적 HTML 보고서를 생성합니다.
*   **[Mermaid 차트](mermaid/)**: API 구조를 시각화하기 위한 다이어그램을 생성합니다.
*   **[추가 형식](more/)**: TOML, JSONL, Postman 컬렉션, 마크다운 테이블 및 특수 필터를 포함한 추가 형식을 살펴보세요.

올바른 출력 형식을 선택하면 개발 프로세스를 간소화하고 Noir가 제공하는 인사이트에 더 쉽게 조치를 취할 수 있습니다.
