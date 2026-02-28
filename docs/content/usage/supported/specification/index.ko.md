+++
title = "지원되는 명세"
description = "OpenAPI, RAML, HAR, GraphQL 등 Noir가 지원하는 API 및 데이터 명세입니다."
weight = 2
sort_by = "weight"

+++

소스 코드 분석 외에도 Noir는 기존 API 문서, 캡처된 네트워크 트래픽 등 다양한 API 및 데이터 명세 형식을 파싱할 수 있습니다.

| 명세 | 형식 | endpoint | method | query | path | body | header | cookie | static_path | websocket |
|---|---|---|---|---|---|---|---|---|---|---|
| GraphQL | GRAPHQL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| HAR | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 2.0 (Swagger) | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 2.0 (Swagger) | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 3.0 | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OpenAPI 3.0 | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Postman Collection | JSON | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| RAML | YAML | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |