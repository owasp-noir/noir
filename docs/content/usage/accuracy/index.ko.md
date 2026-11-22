+++
title = "API 일치도 스코어보드"
description = "고정된 공개 저장소의 API 명세와 코드 분석 결과를 비교한 재현율과 일치도입니다."
weight = 2
+++

실제 저장소에 포함된 OpenAPI 계약과 코드 분석 결과를 소스만 읽어 비교합니다. 테스트 픽스처를 정답으로 사용하지 않습니다. 코퍼스는 저장소 15개와 기술 10개로 구성됩니다. 확인 가능한 계약을 기준으로 선택했으므로 이 수치를 그 프레임워크의 모든 프로젝트에 일반화할 수 없습니다. 아래 표의 기술 식별자와 저장소 메타데이터는 원문을 유지합니다.

<!-- SCOREBOARD -->

Measured: 2026-11-22. Analyzer source: `bd9e6c936808b26689f5b1939676db1876aab621`.

저장소 하나에서 측정한 기술은 단일 데이터 포인트입니다.

| Technology | Repositories | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 1 | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| go_chi | 2 | 264 | 41 | 249 | 86.6% | 51.5% | 262 (51.1%) |
| go_echo | 1 | 149 | 23 | 115 | 86.6% | 56.4% | 4 (1.5%) |
| go_gin | 2 | 238 | 3 | 44 | 98.8% | 84.4% | 230 (81.6%) |
| go_mux | 1 | 26 | 1 | 88 | 96.3% | 22.8% | 0 (0.0%) |
| java_spring | 1 | 182 | 2 | 28 | 98.9% | 86.7% | 0 (0.0%) |
| js_express | 2 | 303 | 128 | 366 | 70.3% | 45.3% | 9 (1.3%) |
| python_django | 2 | 235 | 0 | 300 | 100.0% | 43.9% | 0 (0.0%) |
| python_fastapi | 2 | 348 | 1 | 114 | 99.7% | 75.3% | 0 (0.0%) |
| ts_nestjs | 1 | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |

| Repository | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| InvokeAI | 264 | 1 | 3 | 99.6% | 98.9% | 0 (0.0%) |
| NodeBB | 250 | 128 | 355 | 66.1% | 41.3% | 9 (1.5%) |
| answer | 196 | 3 | 34 | 98.5% | 85.2% | 228 (99.1%) |
| auth | 23 | 41 | 60 | 35.9% | 27.7% | 0 (0.0%) |
| dvws-node | 53 | 0 | 11 | 100.0% | 82.8% | 0 (0.0%) |
| eShop | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| flowable-engine | 182 | 2 | 28 | 98.9% | 86.7% | 0 (0.0%) |
| gotify | 42 | 0 | 10 | 100.0% | 80.8% | 2 (3.8%) |
| immich | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |
| langflow | 84 | 0 | 111 | 100.0% | 43.1% | 0 (0.0%) |
| owncast | 241 | 0 | 189 | 100.0% | 56.0% | 262 (60.9%) |
| podinfo | 26 | 1 | 88 | 96.3% | 22.8% | 0 (0.0%) |
| pokeapi | 102 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| pretalx | 133 | 0 | 300 | 100.0% | 30.7% | 0 (0.0%) |
| vikunja | 149 | 23 | 115 | 86.6% | 56.4% | 4 (1.5%) |

| Technology | Detected / repositories | Other technologies detected | Forced-only rows | Automatic-only rows |
| --- | ---: | --- | ---: | ---: |
| cs_aspnet_core_minimal_api | 1 / 1 | cs_aspnet_core_mvc, http_file, oas3 | 0 | 0 |
| go_chi | 2 / 2 | caddy, go_cli, go_http, js_cli, js_egg, js_http, js_nextjs, oas3, supabase | 0 | 0 |
| go_echo | 1 / 1 | go_cli, go_http, go_huma, oas2 | 0 | 0 |
| go_gin | 2 / 2 | go_cli, go_http, k8s_ingress, oas2 | 0 | 0 |
| go_mux | 1 / 1 | go_cli, grpc, k8s_gateway_api, k8s_ingress, oas2 | 0 | 0 |
| java_spring | 1 / 1 | oas2 | 0 | 0 |
| js_express | 2 / 2 | js_apollo, js_cli, js_socketio, js_sveltekit, oas3, wsdl | 0 | 0 |
| python_django | 2 / 2 | graphql_operation, hasura, js_cli, k8s_ingress, nginx, oas3, python_cli | 0 | 0 |
| python_fastapi | 2 / 2 | oas3, python_cli, python_fastmcp, python_starlette | 0 | 0 |
| ts_nestjs | 1 / 1 | js_express, js_socketio, oas3 | 0 | 0 |

| Repository | Technology | Detected | Other technologies detected | Forced-only rows | Automatic-only rows |
| --- | --- | --- | --- | ---: | ---: |
| InvokeAI | python_fastapi | true | oas3, python_cli, python_starlette | 0 | 0 |
| NodeBB | js_express | true | js_cli, js_socketio, oas3 | 0 | 0 |
| answer | go_gin | true | go_cli, k8s_ingress, oas2 | 0 | 0 |
| auth | go_chi | true | go_cli, go_http, oas3, supabase | 0 | 0 |
| dvws-node | js_express | true | js_apollo, js_sveltekit, oas3, wsdl | 0 | 0 |
| eShop | cs_aspnet_core_minimal_api | true | cs_aspnet_core_mvc, http_file, oas3 | 0 | 0 |
| flowable-engine | java_spring | true | oas2 | 0 | 0 |
| gotify | go_gin | true | go_cli, go_http, oas2 | 0 | 0 |
| immich | ts_nestjs | true | js_express, js_socketio, oas3 | 0 | 0 |
| langflow | python_fastapi | true | oas3, python_cli, python_fastmcp, python_starlette | 0 | 0 |
| owncast | go_chi | true | caddy, go_cli, go_http, js_cli, js_egg, js_http, js_nextjs, oas3 | 0 | 0 |
| podinfo | go_mux | true | go_cli, grpc, k8s_gateway_api, k8s_ingress, oas2 | 0 | 0 |
| pokeapi | python_django | true | graphql_operation, hasura, js_cli, k8s_ingress, nginx, oas3, python_cli | 0 | 0 |
| pretalx | python_django | true | oas3, python_cli | 0 | 0 |
| vikunja | go_echo | true | go_cli, go_http, go_huma, oas2 | 0 | 0 |

| Technology | Inputs on matched rows | Both | Document only | Code only | Recall | Agreement |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | Parameters | 28 | 16 | 0 | 63.6% | 100.0% |
| cs_aspnet_core_minimal_api | Body fields | 38 | 1 | 0 | 97.4% | 100.0% |
| go_chi | Parameters | 31 | 27 | 88 | 53.4% | 26.1% |
| go_chi | Body fields | 16 | 162 | 4 | 9.0% | 80.0% |
| go_echo | Parameters | 128 | 69 | 0 | 65.0% | 100.0% |
| go_echo | Body fields | 0 | 364 | 0 | 0.0% | n/a |
| go_gin | Parameters | 35 | 106 | 5 | 24.8% | 87.5% |
| go_gin | Body fields | 35 | 307 | 1 | 10.2% | 97.2% |
| go_mux | Parameters | 7 | 0 | 0 | 100.0% | 100.0% |
| go_mux | Body fields | 0 | 0 | 0 | n/a | n/a |
| java_spring | Parameters | 544 | 21 | 109 | 96.3% | 83.3% |
| java_spring | Body fields | 378 | 67 | 90 | 84.9% | 80.8% |
| js_express | Parameters | 272 | 18 | 65 | 93.8% | 80.7% |
| js_express | Body fields | 96 | 78 | 19 | 55.2% | 83.5% |
| python_django | Parameters | 331 | 297 | 73 | 52.7% | 81.9% |
| python_django | Body fields | 311 | 142 | 10 | 68.7% | 96.9% |
| python_fastapi | Parameters | 454 | 20 | 9 | 95.8% | 98.1% |
| python_fastapi | Body fields | 360 | 33 | 42 | 91.6% | 89.6% |
| ts_nestjs | Parameters | 245 | 102 | 6 | 70.6% | 97.6% |
| ts_nestjs | Body fields | 221 | 274 | 1 | 44.6% | 99.5% |

| Technology | Both guarded | Both open | Document guarded, code open | Document open, code guarded |
| --- | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 0 | 16 | 0 | 0 |
| go_chi | 120 | 3 | 8 | 133 |
| go_echo | 131 | 11 | 1 | 6 |
| go_gin | 162 | 56 | 10 | 10 |
| go_mux | 0 | 26 | 0 | 0 |
| java_spring | 0 | 0 | 182 | 0 |
| js_express | 8 | 85 | 0 | 210 |
| python_django | 0 | 230 | 0 | 5 |
| python_fastapi | 325 | 17 | 6 | 0 |
| ts_nestjs | 268 | 19 | 0 | 0 |

| Technology | Resolution claim | Marked endpoints | Share of code endpoints |
| --- | --- | ---: | ---: |
| go_chi | `handler:heuristic` | 21 | 4.1% |
| go_chi | `prefix:unresolved` | 241 | 47.0% |
| go_echo | `prefix:unresolved` | 4 | 1.5% |
| go_gin | `handler:heuristic` | 8 | 2.8% |
| go_gin | `prefix:unresolved` | 228 | 80.9% |
| js_express | `prefix:unresolved` | 9 | 1.3% |

- [InvokeAI](https://github.com/invoke-ai/InvokeAI/tree/9264acf9e542d51a21467013029b755686dee375) · `9264acf9e542d51a21467013029b755686dee375` · `python_fastapi` · scope `invokeai/app` · `invokeai/frontend/api/openapi.json`. openapi-checks.yml regenerates the schema from FastAPI and diffs it. Only invokeai/app is scanned; frontend and other packages are excluded.
- [NodeBB](https://github.com/NodeBB/NodeBB/tree/5456eac373abbc93136fed7b02ce8f58060f14cc) · `5456eac373abbc93136fed7b02ce8f58060f14cc` · `js_express` · scope `.` · `public/openapi/read.yaml`, `public/openapi/write.yaml`. test/api/routes.js:24-86 compares mounted Express routes against both committed contracts, with explicit exclusions at lines 62-81. Together they cover the forum read and write APIs; UI, federation and plugin routes remain in scope as undocumented routes. The real /api/v3 mount is retained. install/web.js:63-68 starts a separate setup server and is excluded. Outside this service: `./install`.
- [answer](https://github.com/apache/answer/tree/6744295fa888e0621fc9f9a8ace04f1a4daf8554) · `6744295fa888e0621fc9f9a8ace04f1a4daf8554` · `go_gin` · scope `.` · `docs/swagger.json`. Makefile generate runs go generate; swag annotations live on the handlers for this Gin service. Known stale annotations: personal question page lacks its service prefix; activation uses plural users instead of user; notification config documents POST instead of GET.
- [auth](https://github.com/supabase/auth/tree/3e79d8513b67d7dc3f234153aacc074daf82db5f) · `3e79d8513b67d7dc3f234153aacc074daf82db5f` · `go_chi` · scope `.` · `openapi.yaml`. Maintained beside internal/api; the hosted prefix is declared at openapi.yaml:38 and absent from the root-local router (api.go:219-222,498,520). Reauthenticate has a stale documented verb. Spec rows are compared without the deployment `/auth/v1` prefix.
- [dvws-node](https://github.com/snoopysecurity/dvws-node/tree/4221c04f132960a0ccca4bf5aa5f3a9f53172778) · `4221c04f132960a0ccca4bf5aa5f3a9f53172778` · `js_express` · scope `.` · `docs/openapi/openapi.json`. scripts/generate-openapi.js generates this contract with swagger-autogen from src/routes; test/openapi.test.js checks the document.
- [eShop](https://github.com/dotnet/eShop/tree/913acea66708a59595351174cee9b29f37179d29) · `913acea66708a59595351174cee9b29f37179d29` · `cs_aspnet_core_minimal_api` · scope `src/Catalog.API` · `src/Catalog.API/Catalog.API.json`, `src/Catalog.API/Catalog.API_v2.json`. Catalog.API.csproj exports OpenAPI during build with Microsoft.Extensions.ApiDescription.Server. Both API versions are included; query-parameter version distinctions are outside endpoint scoring. Only Catalog.API source is scanned, not other services or shared default endpoints.
- [flowable-engine](https://github.com/flowable/flowable-engine/tree/055f90ad53a581c76ec2a6f4973acd2498c443fd) · `055f90ad53a581c76ec2a6f4973acd2498c443fd` · `java_spring` · scope `modules/flowable-rest/src/main` · `docs/public-api/references/swagger/process/flowable-swagger-process.yaml`. Hand-written process-service controllers. docs/public-api/references/swagger/README.md:7-13 identifies the stable contract as generated from source annotations with manual corrections; docs/public-api/tools/flowable-oas-generator/pom.xml:51-84 selects this package. The application deployment prefix is declared by modules/flowable-app-rest/src/main/resources/flowable-default.properties:2,43; the scoped controller library registers local paths. Spec rows are compared without the deployment `/flowable-rest/service` prefix.
- [gotify](https://github.com/gotify/server/tree/01086b95a8b69ee87383f6e8bcae601d8c33384b) · `01086b95a8b69ee87383f6e8bcae601d8c33384b` · `go_gin` · scope `.` · `docs/spec.json`. Makefile:41-50 regenerates docs/spec.json from source annotations and fails on a diff. Covers this notification service, including users, clients, applications, messages and plugins; UI and optional transport routes remain in scope. No prefix adjustment. plugin/example/echo/echo.go:74-77 defines an example plugin webhook, not a core service registration, and is excluded. Outside this service: `plugin/example`.
- [immich](https://github.com/immich-app/immich/tree/e5d6eb7be67834f59d90e4b7a86f5dec7ac9af86) · `e5d6eb7be67834f59d90e4b7a86f5dec7ac9af86` · `ts_nestjs` · scope `server` · `open-api/immich-openapi-specs.json`. Generated from server controllers by the OpenAPI tooling; .github/workflows/check-openapi.yml checks contract changes. Only server is scanned.
- [langflow](https://github.com/langflow-ai/langflow/tree/e8bbae8eeb8729abd650f07bfc55957cbdbc1636) · `e8bbae8eeb8729abd650f07bfc55957cbdbc1636` · `python_fastapi` · scope `src/backend/base` · `docs/openapi/openapi.json`. docs/openapi/generate_openapi.py:83-93 writes create_app().openapi(); lines 96-103 select this committed document. Pinned to the schema-generator introduction, before workflow routes moved into the separate lfx package, so src/backend/base contains all service routers (langflow/main.py:532-534). Component examples, frontend and tests are outside scope. No prefix adjustment.
- [owncast](https://github.com/owncast/owncast/tree/c3a9ac1c46c043358fe7382a6d62d5227e4b2efe) · `c3a9ac1c46c043358fe7382a6d62d5227e4b2efe` · `go_chi` · scope `.` · `openapi.yaml`. Makefile api-generate produces the checked-in chi server from this spec; /api is a real mount, not a prefix to strip.
- [podinfo](https://github.com/stefanprodan/podinfo/tree/fd3a834ed8d14b80ea334cf8a2fddd4597924da6) · `fd3a834ed8d14b80ea334cf8a2fddd4597924da6` · `go_mux` · scope `.` · `pkg/api/http/docs/swagger.json`. Makefile swagger regenerates this document from handler annotations; runtime path helpers remain part of the analyzer task. token/validate is annotated POST although registered GET.
- [pokeapi](https://github.com/PokeAPI/pokeapi/tree/8a92bfa7dab2f12b84b5d151562f9857c133ff30) · `8a92bfa7dab2f12b84b5d151562f9857c133ff30` · `python_django` · scope `.` · `openapi.yml`. Makefile openapi-generate uses Django spectacular; describes the REST API, not the separate GraphQL service.
- [pretalx](https://github.com/pretalx/pretalx/tree/1510dea9aafd580d1b2d7b8466736a09cd0298ec) · `1510dea9aafd580d1b2d7b8466736a09cd0298ec` · `python_django` · scope `src/pretalx` · `doc/api/schema.yml`. justfile:125-128 regenerates this committed schema through Django spectacular; src/pretalx/common/management/commands/spectacular.py:9-16 delegates to drf-spectacular. Covers the complete REST API (src/pretalx/urls.py:42 and api/urls.py); the scoped application also contains organiser, agenda and submission UI routes, which remain visible as code-only rows. No prefix adjustment.
- [vikunja](https://github.com/go-vikunja/vikunja/tree/293264397571be437c9bc9a32b4c492bd566dbc2) · `293264397571be437c9bc9a32b4c492bd566dbc2` · `go_echo` · scope `pkg` · `pkg/swagger/swagger.json`. magefile.go Generate.SwaggerDocs runs swag; release automation regenerates and commits pkg/swagger. Only pkg is scanned; standalone example plugins and the frontend are outside this service scope. Known stale annotations: singular image instead of images in the Unsplash proxy; PUT rather than POST for label updates.

<!-- /SCOREBOARD -->

## 측정 방법

[`scripts/scoreboard/corpus.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/corpus.json)에는 저장소 커밋, 코드 기술, 서비스 범위, 선택한 OpenAPI 파일, 선택적 `spec_prefix`와 `exclude_paths`, 짧은 설명만 저장합니다. 제외 경로는 Noir의 기존 `--exclude-path` 옵션으로 전달하는 명시적인 서비스 경계이며 스냅샷 식별자에도 포함됩니다. NodeBB의 별도 웹 설치 서버(`install/web.js:63-68`)와 Gotify의 예제 플러그인(`plugin/example/echo/echo.go:74-77`)은 평가하는 서비스 밖이므로 제외합니다. 실행기는 고정된 커밋을 얕게 가져와 그 서비스와 선택한 명세 파일을 임시 공간에 내보냅니다. 다른 OpenAPI 진입 문서는 제거합니다. 평가 대상 분석기의 경로 소스가 아닌 WebAssembly(`*.wasm`)와 CSV 데이터셋(`*.csv`)은 제외합니다. 스캔 오류가 있으면 게시용 파일 생성을 중단합니다. 코퍼스 애플리케이션은 빌드하거나 설치하거나 실행하지 않습니다.

기존 엔드포인트 지표는 고정된 코드 분석기를 강제 지정하고 OAS2/OAS3 탐지기를 활성화한 통합 스캔으로 계산합니다. 최적화된 HTTP 행의 `details.technologies`에 평가 대상 코드 기술과 `spec` 기여자가 함께 있으면 **matched**, 코드 기여자만 없으면 **spec-only**, 명세 기여자만 없으면 **code-only**입니다. 단일 기여자는 `details.technology`에서 읽습니다. 기술별 비율은 저장소별 개수를 합산한 뒤 계산합니다.

- **Recall(재현율)** = matched / (matched + spec-only). 문서의 HTTP 동작 중 코드 분석기가 찾은 비율입니다.
- **Agreement(일치도)** = matched / (matched + code-only). 코드 출력 중 명세에도 있는 비율입니다. 일치한 명세 동작이 유효하다는 전제에서 정밀도의 하한이며, 측정된 정밀도는 아닙니다. 실제로 존재하지만 문서화되지 않은 health, admin, UI 경로도 이 값을 낮춥니다.
- **Marked(표시된 행)**는 비어 있지 않은 `resolution` 맵이 있는 코드 엔드포인트를 한 번씩 셉니다. 각 `claim:status`도 같은 코드 분모로 별도 집계하므로 서로 겹칠 수 있습니다. 표시가 없다고 정확성을 보장하지 않습니다. 이 스캔에서는 AI 컨텍스트와 태거를 끕니다.
- 분모가 0이면 결과는 `null`, 표는 `n/a`입니다. Noir가 가져온 HTTP 행만 분모에 들어갑니다. 스키마 타입, 값, WebSocket 동작, 실제 실행 시 접근 가능성은 측정 범위 밖입니다.

### 탐지, 파라미터와 인증 가드

**탐지.** 같은 파일과 제외 경로를 사용해 기술 제한 없이 다시 스캔합니다. 탐지 목록에는 엔드포인트를 하나도 출력하지 않은 기술도 들어갑니다. 저장소와 기술별로 고정된 기술의 탐지 여부와 OpenAPI를 포함해 해당 저장소의 코드 기술 목록 밖에서 탐지된 기술을 기록합니다. 강제 스캔 또는 자동 스캔에만 있는 행은 해당 기술이 기여한 HTTP 행끼리 비교해 셉니다. 메서드, Noir가 경로 세그먼트 전체를 차지하는 변수를 정규화한 URL, 해당 기술의 출처 범위를 사용하며 같은 키가 여러 번 나타나면 각각 셉니다. 차이가 난 메서드, URL, 소스 위치는 `tmp/scoreboard/`의 저장소별 탐지 파일에 있습니다. 기술별 집계는 차이가 난 행 수를 합산하고 다른 탐지 기술의 합집합을 표시합니다. 추가로 탐지된 기술도 실제 서비스에 쓰일 수 있습니다.

**파라미터.** 명세가 보안 스킴으로 선언한 자격 증명(`Authorization` 헤더, API 키 헤더나 쿠키)은 양쪽 모두 이 비교에서 제외하며, 아래 guard 집계가 이를 다룹니다. 기존 통합 스캔에서 일치한 HTTP 행마다 해당 기술만 스캔한 코드 결과와 OAS만 스캔한 명세 결과를 찾습니다. 메서드와 Noir의 경로 변수 정규화를 사용하고, 같은 형태의 후보가 여러 개이면 통합 행에 기록된 소스 위치와 정확한 URL로 구분합니다. 행을 찾을 수 없거나 하나로 특정할 수 없으면 결과 생성을 중단합니다. 각 행에서 (위치, 이름) 쌍의 중복을 제거합니다. 헤더 이름은 대소문자를 무시합니다. 세그먼트 전체를 차지하는 경로 변수는 양쪽 URL에서 차지하는 순서로 비교합니다. 나머지 경로 이름과 쿼리·쿠키 이름은 대소문자까지 같아야 합니다. 요청 본문은 별도로 집계하며 JSON, body, form의 필드 이름이 같으면 인코딩에 관계없이 일치합니다. JSON/body 입력의 이름이 `body`이면 본문 전체와 구별할 수 없어 양쪽 모두에서 제외합니다. 실제 JSON 속성 이름이 `body`인 경우도 해당하며 반대쪽에서 식별한 필드는 그대로 셉니다. Noir는 URL에서 경로 변수를, 보안 스킴에서 인증 입력을 추론할 수 있습니다. 각 집합의 일치 수를 전체 행에 걸쳐 합산한 뒤 명세 쪽 개수로 나누면 recall, 코드 쪽 개수로 나누면 agreement입니다.

**인증 가드.** OAS 전용 스캔에서는 `oas2_access` 또는 `oas3_access`가 붙인 `auth` 태그를 읽습니다. 동작에 선언한 `security`가 전역 설정보다 우선합니다. 명시적인 빈 목록, 익명을 허용하는 `{}` 대안, 선언이 없는 경우는 공개로 셉니다. 스킴 목록이 있으면 Noir는 목록에 없는 스킴을 포함한 대안을 제외합니다. 코드 전용 스캔은 `--use-all-taggers`를 켜고 이름이 `_auth`로 끝나는 프레임워크 태거가 엔드포인트에 `auth`를 붙였을 때 가드가 있다고 봅니다. 인가 전용 태그와 인증 정보 파라미터는 이 집계에서 제외합니다. 일치한 행 하나당 명세와 코드의 가드 유무 조합 네 가지 중 하나를 셉니다. 코드 쪽의 공개 판정은 Noir가 인증 가드를 찾지 못했다는 뜻입니다. 오래된 명세나 태거의 탐지 한계로도 차이가 날 수 있습니다.

현재 코퍼스의 저장소마다 고정된 코드 기술이 하나이므로 스캔 횟수는 저장소당 1회에서 4회, 15개 저장소 전체에서 60회로 늘어납니다. 스캔 시간은 약 4배로 예상합니다. 자동 탐지와 태깅에 드는 시간은 서비스마다 다르며 체크아웃과 파일 추출은 한 번만 수행합니다.

### 명시적인 배포 접두사 보정

Supabase Auth는 `spec_prefix: "/auth/v1"`을 선언합니다. `openapi.yaml:37-38`은 호스팅 서버 URL을 `https://{project}.supabase.co/auth/v1`로 지정합니다. 서비스는 로컬 경로를 등록합니다. `internal/api/api.go:219-222`는 `/` 라우터를 열고 `:268`은 `/token`을 등록합니다. `internal/api/router.go:17-31`은 경로를 그대로 chi에 넘깁니다. API는 이 라우터에 직접 전달하고(`api.go:498,520`), `cmd/serve_cmd.go:63-75`는 `/auth/v1` 마운트 없이 API를 HTTP 서버 핸들러로 설치합니다. 따라서 이 접두사는 소스에서 누락된 경로가 아닌 호스팅 배포 경계입니다.

실행기는 이 명세를 가져오기 전에 **임시 복사본의 루트 서버 URL**에서 명시된 접두사만 제거합니다. 그러면 Noir가 자체 병합을 하기 전에 명세 행이 로컬 경로가 됩니다. 선언된 모든 서버 경로가 설정한 접두사와 정확히 같은지 검사하며 경로·동작별 서버 재정의가 있으면 거부합니다. 원본 체크아웃과 코드 행은 바꾸지 않고 별도 엔드포인트 매처도 추가하지 않습니다. 보정한 명세의 행 번호는 임시 복사본을 가리키며, 코드 위치는 고정된 원본 소스를 가리킵니다.

Flowable은 프로세스 컨트롤러 라이브러리에 `spec_prefix: "/flowable-rest/service"`를 선언합니다. 커밋된 Swagger 2 문서의 20행이 이 `basePath`를 지정합니다. 별도 REST 애플리케이션은 `modules/flowable-app-rest/src/main/resources/flowable-default.properties:2`에서 `/flowable-rest` 컨텍스트를, 43행에서 `/service` 서블릿 경로를 설정합니다. Spring Boot 자동 구성 모듈의 `BaseRestApiConfiguration.java:41-48`은 이 서블릿 매핑을 설치합니다. 배포 설정은 스캔 범위인 `modules/flowable-rest/src/main` 라이브러리 밖에 있으며, 직접 작성한 컨트롤러는 로컬 경로를 등록합니다(예: `DeploymentCollectionResource.java:106`). 실행기는 Swagger 2의 `basePath`가 정확히 일치하는지 확인하고 임시 복사본의 값만 `/`로 바꿉니다. 동작 경로는 바꾸지 않습니다.

Owncast는 다릅니다. `webserver/router/router.go:93`은 생성된 API를 `/api/`에 마운트합니다. 명세의 `/api`는 소스에도 있으므로 유지합니다. Supabase Auth와 Flowable에만 접두사 보정이 있습니다. 파라미터 표기는 Noir 자체 정규화를 사용하며 대소문자, 끝 슬래시, `ANY`, 와일드카드, 상수 접두사, 게이트웨이 재작성 매칭을 추가하지 않습니다. 게이트웨이 규칙은 API 동작과 일대일로 대응하지 않아 제외합니다.

### 소스 감사

아래 날짜가 있는 표는 측정 스냅샷에 대한 수동 감사입니다. 초기 감사는 기술별로 불일치 행을 최대 25개씩 확인했습니다. 저장소와 spec-only/code-only 조합에 표본 수를 배분하고 정렬된 목록에서 일정 간격으로 선택합니다. 전체 오류 추정치가 아닌 표본 개수이며, 같은 동작이 양쪽 불일치에 포함될 수 있습니다.

분류는 분석기 누락, 분석기 오탐, 오래되거나 잘못된 명세, 문서화되지 않은 경로, 분석기 오류가 아닌 접두사·메서드·끝 슬래시 차이, 기타입니다. 분류는 비율을 바꾸지 않습니다. 행별 근거는 커밋하지 않습니다. 새 측정을 게시하기 전에 바뀐 행을 다시 확인하고 이 날짜가 있는 표를 갱신해야 합니다. 레시피는 측정값만 생성하며 수동 감사를 재생성하지 않습니다.

<!-- AUDIT -->

감사 날짜: 2026-11-15. 153개 불일치 행을 고정된 소스와 대조했습니다.

| Technology | Audited | Analyzer miss | Stale spec | Undocumented route | Prefix/method/slash | Other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 0 | 0 | 0 | 0 | 0 | 0 |
| go_chi | 25 | 1 | 2 | 10 | 11 | 1 |
| go_echo | 25 | 9 | 4 | 12 | 0 | 0 |
| go_gin | 25 | 0 | 4 | 21 | 0 | 0 |
| go_mux | 25 | 0 | 1 | 24 | 0 | 0 |
| js_express | 11 | 0 | 0 | 11 | 0 | 0 |
| python_django | 0 | 0 | 0 | 0 | 0 | 0 |
| python_fastapi | 25 | 25 | 0 | 0 | 0 | 0 |
| ts_nestjs | 17 | 0 | 0 | 17 | 0 | 0 |

이 감사는 분석기 리비전 `8184cd4`에서 했습니다. 여기서 찾은 누락 중 두 가지는 그 뒤 고쳐졌습니다. FastAPI 행의 누락 25건은 모두 InvokeAI의 `/api` 접두사 손실([#3614](https://github.com/owasp-noir/noir/issues/3614))이었고, go_chi의 누락은 supabase/auth의 SCIM 접두사([#3616](https://github.com/owasp-noir/noir/issues/3616))였습니다. FastAPI에 남은 불일치 4건은 다시 감사하지 않았습니다. 나머지 끝 슬래시 차이는 보정하지 않습니다. Express 불일치 11개 행은 모두 감사했습니다.

확장 감사: 2026-11-15, 분석기 리비전 `54ff7225277f691ac19816faad875c52979e39c0`. 새로 고정한 저장소 5개의 불일치 행 137개를 추가로 소스와 대조했습니다. langflow 행은 2026-11-16에 `830b4cfce775d24812f4b0305df6fc24359dcdcb`에서 다시 감사했습니다. 각 저장소의 양쪽을 별도로 표본 추출합니다. 한쪽이 25개 이하면 전부, 더 많으면 정렬된 목록에서 `floor(i * count / 25)` 위치의 25개를 확인합니다. 위의 과거 표는 유지하며 기존 코퍼스를 현재 리비전으로 다시 감사했다는 뜻이 아닙니다. 기존 저장소 10개의 모든 측정값 필드는 커밋된 기준 결과와 같습니다.

| Repository | Spec-only audited | Code-only audited | Analyzer miss | Analyzer false positive | Stale spec | Undocumented route | Prefix/method/slash | Other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| flowable-engine | 2 | 25 | 0 | 0 | 0 | 24 | 0 | 3 |
| NodeBB | 25 | 25 | 23 | 17 | 1 | 8 | 1 | 0 |
| gotify | 0 | 10 | 0 | 0 | 0 | 10 | 0 | 0 |
| langflow | 0 | 25 | 0 | 0 | 0 | 24 | 0 | 1 |
| pretalx | 0 | 25 | 0 | 0 | 0 | 25 | 0 | 0 |

Flowable의 기타 3건은 명세의 리터럴 `users` 동작 2개와 표본에 든 `{family}` 컨트롤러 행 1개입니다. `ProcessInstanceIdentityLinkResource.java:49,73,98-100`은 경로를 등록하고 `users` 또는 `groups`인지 확인합니다. 리터럴과 파라미터의 특수화 차이입니다. 나머지 표본 동작은 실제 등록되어 있지만 계약에는 없습니다. Gotify 표본은 UI·문서, 명시적인 HEAD health, 조건부 MCP 경로입니다. Pretalx 표본은 REST 계약 밖의 주최자·일정·발표 제출 UI 경로입니다.

NodeBB는 라우트 모듈마다 마운트 이름을 인자로 넘깁니다. `src/routes/index.js:236-254`는 기본값이 `admin`, `user`, `tags` 등인 플러그인 훅에서 이름을 받고, `src/routes/admin.js` 같은 모듈은 경로를 `/${name}/...`로 만듭니다. 명세는 기본 이름으로 적혀 있고 Noir는 `/api/{name}/...`와 `/{name}/...`를 출력하므로, 같은 라우트가 불일치 양쪽에 한 번씩 나타납니다. 표본의 누락 23건과 오탐 16건이 이 원인입니다. 추가 오탐 1건은 `index.js:136`의 미들웨어 전용 `router.all` 정규식입니다. `src/middleware/index.js:130-133`은 `next()`만 호출합니다. 오래된 명세 1건은 삭제된 읽기 API의 세션 삭제 경로이며, 대체 경로는 `src/routes/write/users.js:66`에 등록되어 있습니다. 접두사 차이 1건은 `/ping`으로, 소스가 설정 가능한 `relative_path`를 앞에 붙입니다(`src/webserver.js:152,191`).

Langflow는 처음에 명세의 84개 동작 중 4개만 일치했습니다. 패키지 `__init__.py`에서 다시 내보낸 라우터가 `/api/v1`과 `/api/v2`를 잃었기 때문입니다([#3625](https://github.com/owasp-noir/noir/issues/3625)). 이를 고친 뒤에는 84개가 모두 일치합니다. 표본으로 본 코드 전용 25행 중 24행은 프로젝트가 `include_in_schema=False`로 명세에서 숨긴 라우트입니다. 라우터에 지정한 경우(`api/v1/deployments.py:36`, `models.py:24`, `knowledge_bases.py:35`)와 라우트에 지정한 경우가 있습니다. 나머지 1행은 `main.py:584`의 정적 파일 마운트입니다.

<!-- /AUDIT -->

### 다시 실행하기와 산출물

```sh
just scoreboard
bash docs/scripts/check_doc_parity.sh
hwaro build -i docs
```

레시피는 필요할 때 실행하며 컴파일 게이트를 거치는 `build-release`에 의존합니다. git, tar, 캐시에 없는 커밋을 가져올 네트워크가 필요합니다. 체크아웃과 복사본은 `$TMPDIR/noir-codex-scoreboard/`에 보관합니다. `TMPDIR`이 없으면 `/tmp/noir-codex-scoreboard/`를 사용합니다. 저장소별 matched/spec-only/code-only 목록과 기술별 감사 표본은 git에서 제외된 `tmp/scoreboard/`에 작성하며 커밋하지 않습니다.

작은 회귀 비교 스냅샷인 [`scripts/scoreboard/results.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/results.json)에는 개수, 비율, 표시 개수, 저장소 커밋, 날짜, 분석기 리비전이 있습니다. 분석기 리비전과 코퍼스가 같으면 스냅샷 날짜를 유지합니다. 실행 전에 분석기와 의존성 변경을 커밋해야 합니다. 수정되거나 추적되지 않은 `src` 파일과 변경된 shard 매니페스트가 있으면 거부합니다. 출력은 정렬하며 실행 시간과 절대 임시 경로를 넣지 않습니다.

Hwaro는 커밋된 마크다운 표를 렌더링하고 빌드 시 결과 JSON을 읽지 않습니다. 따라서 결과 파일은 `docs/data/` 대신 코퍼스와 함께 보관합니다. CI의 지원 기술 문서 생성기는 이 레시피를 호출하거나 코퍼스를 가져오지 않습니다. 사이트는 오프라인으로 빌드할 수 있습니다.

### 선택하지 않은 후보

- **spring-petclinic-rest**: 메서드 매핑은 빌드 시 명세에서 생성하며 체크아웃에 없습니다. 그래서 0%가 나와도 분석기 실패가 아닙니다.
- **juice-shop**: 명세는 B2B 주문만 다룹니다. 서비스 전체를 평가하면 일치도가 주로 명세의 좁은 범위를 반영합니다.
- **이전 Spring 대체 후보**: 초기 조사에서 spring-cloud-dataflow, ThingsBoard, Stirling-PDF에는 적합한 커밋된 계약이 없었습니다. 이번 확장에는 동작 15개의 Flowable decision 계약 대신 동작 184개의 process 서비스 Swagger 2 계약을 넣었습니다. OpenAPI 3 대안은 계속 제외합니다. `docs/public-api/references/openapi/README.md:5-7`이 불완전하다고 명시합니다. 안정된 Swagger 문서는 소스 주석에서 생성한 뒤 수동으로 보정한다고 `references/swagger/README.md:7-13`에 설명하며, 생성기의 `tools/flowable-oas-generator/pom.xml:51-84`가 프로세스 컨트롤러 패키지를 지정합니다.
- **두 번째 Express 후보**: Directus의 계약은 넓은 범위를 다루지만 현재 Access, Policies, Panels, Notifications, Deployment API가 없고 오래된 OAuth·관계 경로가 남아 있습니다. 추가하지 않았으며 이번에 NodeBB를 두 번째 Express 데이터 포인트로 넣었습니다. RealWorld Express 앱에는 커밋된 OpenAPI 문서가 없었습니다.
- **OWASP/crAPI**: 공유 명세가 여러 서비스에 걸쳐 있어 한 코드 기술의 별도 분모로 쓸 수 없습니다.
- **spring-petclinic-microservices**: 확인한 커밋에 OpenAPI 문서가 없습니다.
- **VAmPI**: 독립적인 Flask 선언 대신 같은 명세로 Connexion이 경로를 생성합니다.
- **shlink**: 코퍼스가 이미 충분한 기술을 다뤄서 넣지 않았습니다. 명세가 오래됐기 때문은 아닙니다.

이번 확장에서 확인했지만 넣지 않은 후보는 다음과 같습니다. apache/fineract(Spring 매핑이 아닌 JAX-RS `@Path` 리소스), novuhq/novu(내보내기가 API 키 인증 없는 엔드포인트를 제거), thomiceli/opengist(문서가 토큰 API만 다루고 라우트와 대조하는 검사가 없음), dyrector-io/dyrectorio(Swagger 설정만 커밋되어 있고 생성된 문서는 없음), 그리고 PrefectHQ/prefect, freqtrade/freqtrade, healthchecks/healthchecks, PostHog/posthog, wger-project/wger, statping-ng/statping-ng(커밋된 서비스 OpenAPI 문서 없음)입니다. Langflow는 스키마 생성기를 도입한 커밋에 고정했습니다. 현재 head에서는 워크플로 라우트가 스캔 범위 밖의 별도 `lfx` 패키지에서 옵니다. 이 커밋은 점수를 보기 전에 골랐으며, 현재 Langflow를 측정한 결과는 아닙니다.
