+++
title = "출력 형식"
description = "Noir가 내보낼 수 있는 출력 형식: JSON, YAML, TOML, OpenAPI(OAS), SARIF, HTML 등."
weight = 2
sort_by = "weight"

+++

스캔 결과는 다음 단계가 필요로 하는 모양 그대로 내보낼 수 있습니다. 자동화라면 기계가 읽는 형식으로, 리뷰라면 사람이 읽는 형식으로. `-f` 플래그로 형식을 고릅니다.

## 형식 선택 가이드

| 사용 사례 | 추천 형식 | 플래그 |
|---|---|---|
| 스크립트/도구 연동 | [JSON](json/) | `-f json` |
| CI/CD 보안 리포팅 | [SARIF](sarif/) | `-f sarif` |
| API 문서 생성 | [OpenAPI](openapi/) | `-f oas3` |
| 빠른 엔드포인트 테스트 | [cURL](curl/) / HTTPie / PowerShell | `-f curl` |
| 모바일 진입점 실행 | [ADB](curl/#adb-android) (Android) / [simctl](curl/#simctl-ios) (iOS) | `-f adb` / `-f simctl` |
| 사람이 읽기 쉬운 검토 | [YAML](yaml/) | `-f yaml` |
| 설정 스타일 출력 | [기타](more/) (TOML) | `-f toml` |
| Postman으로 가져오기 | [기타](more/) (Postman Collection) | `-f postman` |
| 시각적 보고서 공유 | [HTML](html/) | `-f html` |
| API 구조 시각화 | [Mermaid](mermaid/) | `-f mermaid` |
| URL이나 파라미터만 추출 | [기타](more/) (필터) | `-f only-url` |

## 사용 가능한 형식

*   **[HTTP 클라이언트 명령](curl/)**: 엔드포인트 테스트용 cURL, HTTPie, PowerShell 명령. 모바일 딥링크·인텐트·콘텐츠 프로바이더를 실행하는 [ADB](curl/#adb-android)(Android)·[simctl](curl/#simctl-ios)(iOS) 명령도 만들어 줍니다.
*   **[JSON 및 JSONL](json/)**: 다른 도구나 스크립트로 파이프할 때.
*   **[YAML](yaml/)**: 사람이 직접 훑어볼 때 JSON보다 읽기 편한 형식.
*   **[OpenAPI 명세(OAS)](openapi/)**: 코드에서 생성한 OpenAPI 문서. API 문서화나 보안 도구 임포트에 사용.
*   **[SARIF](sarif/)**: CI/CD 보안 대시보드가 받아들이는 표준 형식.
*   **[HTML 보고서](html/)**: 단일 파일로 완결되는 인터랙티브 HTML 리포트.
*   **[Mermaid 차트](mermaid/)**: API 구조 다이어그램.
*   **[추가 형식](more/)**: TOML, JSONL, Postman 컬렉션, 마크다운 테이블, 출력 필터.
