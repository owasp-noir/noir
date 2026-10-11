+++
title = "출력 형식"
description = "Noir가 내보낼 수 있는 출력 형식: JSON, YAML, TOML, OpenAPI(OAS), SARIF, HTML 등."
weight = 2
sort_by = "weight"

+++

스캔 결과는 다음 단계에 맞는 모양으로 내보낼 수 있습니다. 자동화에는 기계가 읽는 형식을, 리뷰에는 사람이 읽기 쉬운 형식을 쓰면 됩니다. 형식은 `-f`로 고릅니다.

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
| 시각적 리포트 공유 | [HTML](html/) | `-f html` |
| API 구조 시각화 | [Mermaid](mermaid/) | `-f mermaid` |
| URL이나 파라미터만 추출 | [기타](more/) (필터) | `-f only-url` |

## 형식별 요청 본문 지원

모든 형식이 모든 `param_type`을 실제 요청 본문으로 만들지는 않습니다. 아래 표로 빠르게 확인하세요(✅ = 요청 본문/multipart 파트로 출력, ➖ = 엔드포인트 기록에만 남거나 해당 없음).

| `param_type` | `json` / `yaml` / plain | `oas2` / `oas3` | `postman` | `curl` / `httpie` / `powershell` / HTML copy-as-curl |
|---|---|---|---|---|
| `json` | ✅ (타입 필드) | ✅ `application/json` | ✅ raw JSON | ✅ JSON 본문 |
| `form` | ✅ (타입 필드) | ✅ urlencoded 또는 multipart | ✅ `urlencoded` | ✅ urlencoded 본문 |
| `file` | ✅ (타입 필드) | ✅ multipart `format: binary` | ✅ `formdata` file | ✅ multipart 업로드 |
| `xml` | ✅ (타입 필드) | ✅ `application/xml` | ✅ raw XML (비어 있으면 `<name/>`) | ➖ 명령에 본문으로 넣지 않음. OAS / Postman / JSON 사용 |

자세한 내용: [cURL](curl/), [OpenAPI](openapi/), [Postman](more/).

## 사용 가능한 형식

`-f`에 쓸 수 있는 모든 값입니다(`noir list formats`도 같은 목록을 보여줍니다).

| 형식 | 출력 | 페이지 |
|---|---|---|
| `plain` | 일반 텍스트(기본값) | [기타](more/) |
| `json`, `jsonl` | JSON, JSON Lines | [JSON 및 JSONL](json/) |
| `yaml` | YAML | [YAML](yaml/) |
| `toml` | TOML | [기타](more/) |
| `markdown-table` | 마크다운 테이블 | [기타](more/) |
| `sarif` | SARIF v2.1.0 | [SARIF](sarif/) |
| `html` | 단일 파일 HTML 리포트 | [HTML](html/) |
| `curl`, `httpie`, `powershell` | HTTP 클라이언트 명령 | [HTTP 클라이언트 명령](curl/) |
| `adb`, `simctl` | 모바일 진입점용 Android / iOS 실행 명령 | [HTTP 클라이언트 명령](curl/#adb-android) |
| `oas2`, `oas3` | OpenAPI 2.0(Swagger) / 3.x | [OpenAPI](openapi/) |
| `postman` | Postman 컬렉션 | [기타](more/) |
| `only-url`, `only-param`, `only-header`, `only-cookie`, `only-tag` | 한 줄에 값 하나 | [기타](more/) |
| `mermaid` | Mermaid 마인드맵 | [Mermaid](mermaid/) |
