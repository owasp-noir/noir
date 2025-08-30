+++
title = "지원되는 명세"
description = "이 페이지는 OpenAPI(Swagger), RAML, HAR, GraphQL을 포함하여 Noir가 지원하는 API 및 데이터 명세에 대한 자세한 개요를 제공합니다. 자세한 정보는 호환성 테이블을 참조하세요."
weight = 2
sort_by = "weight"

[extra]
+++

소스 코드를 직접 분석하는 것 외에도 Noir는 다양한 API 및 데이터 명세 형식을 파싱할 수 있습니다. 이를 통해 Noir를 사용하여 기존 API 문서, 캡처된 네트워크 트래픽 등을 분석할 수 있습니다.

이 섹션은 Noir가 지원하는 다양한 명세에 대한 호환성 테이블을 제공합니다.

| 명세 | 형식 | endpoint | method | query | path | body | header | cookie | static_path | websocket |
|---|---|---|---|---|---|---|---|---|---|---|
| GraphQL | GRAPHQL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| HAR | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 2.0 (Swagger) | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 2.0 (Swagger) | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 3.0 | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 3.0 | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| RAML | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |