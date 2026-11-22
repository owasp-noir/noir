+++
title = "API agreement scoreboard"
description = "Code analyzer recall and agreement against pinned repositories' own API specifications."
weight = 2
+++

This source-only measurement compares code analyzers with the OpenAPI contracts kept in real repositories. Fixtures are not ground truth. The corpus pins 17 repositories across 10 technologies. listmonk joins Vikunja for Echo and Meshery joins podinfo for Gorilla mux. Flowable is the sole Spring pin. ASP.NET Core minimal APIs and NestJS each have one pin. The tables show the pins included in the dated run. It is selected for inspectable contracts; its numbers do not represent all projects using a framework.

<!-- SCOREBOARD -->

Measured: 2026-11-22. Analyzer source: `cf17712744df4334c00705d50f8ec7411f7b7820`.

A technology measured on one repository is a single data point.

| Technology | Repositories | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 1 | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| go_chi | 2 | 264 | 41 | 249 | 86.6% | 51.5% | 21 (4.1%) |
| go_echo | 2 | 225 | 19 | 233 | 92.2% | 49.1% | 156 (34.1%) |
| go_gin | 2 | 238 | 3 | 44 | 98.8% | 84.4% | 230 (81.6%) |
| go_mux | 2 | 91 | 64 | 286 | 58.7% | 24.1% | 108 (28.6%) |
| java_spring | 1 | 182 | 2 | 28 | 98.9% | 86.7% | 0 (0.0%) |
| js_express | 2 | 411 | 20 | 264 | 95.4% | 60.9% | 228 (33.8%) |
| python_django | 2 | 235 | 0 | 300 | 100.0% | 43.9% | 1 (0.2%) |
| python_fastapi | 2 | 348 | 1 | 114 | 99.7% | 75.3% | 21 (4.5%) |
| ts_nestjs | 1 | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |

| Repository | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| InvokeAI | 264 | 1 | 3 | 99.6% | 98.9% | 0 (0.0%) |
| NodeBB | 358 | 20 | 253 | 94.7% | 58.6% | 228 (37.3%) |
| answer | 196 | 3 | 34 | 98.5% | 85.2% | 228 (99.1%) |
| auth | 23 | 41 | 60 | 35.9% | 27.7% | 0 (0.0%) |
| dvws-node | 53 | 0 | 11 | 100.0% | 82.8% | 0 (0.0%) |
| eShop | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| flowable-engine | 182 | 2 | 28 | 98.9% | 86.7% | 0 (0.0%) |
| gotify | 42 | 0 | 10 | 100.0% | 80.8% | 2 (3.8%) |
| immich | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |
| langflow | 84 | 0 | 111 | 100.0% | 43.1% | 21 (10.8%) |
| listmonk | 72 | 0 | 118 | 100.0% | 37.9% | 151 (79.5%) |
| meshery | 65 | 63 | 198 | 50.8% | 24.7% | 0 (0.0%) |
| owncast | 241 | 0 | 189 | 100.0% | 56.0% | 21 (4.9%) |
| podinfo | 26 | 1 | 88 | 96.3% | 22.8% | 108 (94.7%) |
| pokeapi | 102 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| pretalx | 133 | 0 | 300 | 100.0% | 30.7% | 1 (0.2%) |
| vikunja | 153 | 19 | 115 | 89.0% | 57.1% | 5 (1.9%) |

| Scope | Estimated precision | Estimated recall | Marked matched / code-only |
| --- | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 100.0% (n=0, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| go_chi | 100.0% (n=17, 0 unlabelled, 0 undecided) | 100.0% (n=8, 0 unlabelled, 0 undecided) | 0 / 21 |
| go_echo | 100.0% (n=17, 0 unlabelled, 0 undecided) | 95.0% (n=8, 0 unlabelled, 0 undecided) | 64 / 92 |
| go_gin | 100.0% (n=22, 0 unlabelled, 0 undecided) | 100.0% (n=3, 0 unlabelled, 0 undecided) | 198 / 32 |
| go_mux | 100.0% (n=16, 0 unlabelled, 0 undecided) | 74.3% (n=9, 0 unlabelled, 0 undecided) | 26 / 82 |
| java_spring | 100.0% (n=23, 0 unlabelled, 0 undecided) | 100.0% (n=2, 0 unlabelled, 0 undecided) | 0 / 0 |
| js_express | 91.7% (n=17, 0 unlabelled, 0 undecided) | 99.4% (n=8, 0 unlabelled, 0 undecided) | 108 / 120 |
| python_django | 100.0% (n=25, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 1 |
| python_fastapi | 100.0% (n=24, 0 unlabelled, 0 undecided) | 100.0% (n=1, 0 unlabelled, 0 undecided) | 19 / 2 |
| ts_nestjs | 100.0% (n=17, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| InvokeAI | 100.0% (n=3, 0 unlabelled, 0 undecided) | 100.0% (n=1, 0 unlabelled, 0 undecided) | 0 / 0 |
| NodeBB | 90.8% (n=9, 0 unlabelled, 0 undecided) | 99.3% (n=8, 0 unlabelled, 0 undecided) | 108 / 120 |
| answer | 100.0% (n=12, 0 unlabelled, 0 undecided) | 100.0% (n=3, 0 unlabelled, 0 undecided) | 196 / 32 |
| auth | 100.0% (n=9, 0 unlabelled, 0 undecided) | 100.0% (n=8, 0 unlabelled, 0 undecided) | 0 / 0 |
| dvws-node | 100.0% (n=8, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| eShop | 100.0% (n=0, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| flowable-engine | 100.0% (n=23, 0 unlabelled, 0 undecided) | 100.0% (n=2, 0 unlabelled, 0 undecided) | 0 / 0 |
| gotify | 100.0% (n=10, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 2 / 0 |
| immich | 100.0% (n=17, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| langflow | 100.0% (n=21, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 19 / 2 |
| listmonk | 100.0% (n=9, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 64 / 87 |
| meshery | 100.0% (n=8, 0 unlabelled, 0 undecided) | 67.4% (n=8, 0 unlabelled, 0 undecided) | 0 / 0 |
| owncast | 100.0% (n=8, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 21 |
| podinfo | 100.0% (n=8, 0 unlabelled, 0 undecided) | 100.0% (n=1, 0 unlabelled, 0 undecided) | 26 / 82 |
| pokeapi | 100.0% (n=0, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 0 |
| pretalx | 100.0% (n=25, 0 unlabelled, 0 undecided) | 100.0% (n=0, 0 unlabelled, 0 undecided) | 0 / 1 |
| vikunja | 100.0% (n=8, 0 unlabelled, 0 undecided) | 92.8% (n=8, 0 unlabelled, 0 undecided) | 0 / 5 |
| Total | 98.5% (n=178, 0 unlabelled, 0 undecided) | 98.0% (n=39, 0 unlabelled, 0 undecided) | 415 / 350 |

| Technology | Detected / repositories | Other technologies detected | Forced-only rows | Automatic-only rows |
| --- | ---: | --- | ---: | ---: |
| cs_aspnet_core_minimal_api | 1 / 1 | http_file, oas3 | 0 | 0 |
| go_chi | 2 / 2 | caddy, go_cli, go_http, js_cli, js_http, js_nextjs, oas3 | 0 | 0 |
| go_echo | 2 / 2 | go_cli, go_http, go_huma, oas2, oas3 | 0 | 0 |
| go_gin | 2 / 2 | go_cli, go_http, k8s_ingress, oas2 | 0 | 0 |
| go_mux | 2 / 2 | go_cli, graphql_sdl, grpc, k8s_gateway_api, k8s_ingress, oas2, oas3 | 0 | 0 |
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
| auth | go_chi | true | go_cli, go_http, oas3 | 0 | 0 |
| dvws-node | js_express | true | js_apollo, js_sveltekit, oas3, wsdl | 0 | 0 |
| eShop | cs_aspnet_core_minimal_api | true | http_file, oas3 | 0 | 0 |
| flowable-engine | java_spring | true | oas2 | 0 | 0 |
| gotify | go_gin | true | go_cli, go_http, oas2 | 0 | 0 |
| immich | ts_nestjs | true | js_express, js_socketio, oas3 | 0 | 0 |
| langflow | python_fastapi | true | oas3, python_cli, python_fastmcp, python_starlette | 0 | 0 |
| listmonk | go_echo | true | go_cli, oas3 | 0 | 0 |
| meshery | go_mux | true | graphql_sdl, grpc, oas3 | 0 | 0 |
| owncast | go_chi | true | caddy, go_cli, go_http, js_cli, js_http, js_nextjs, oas3 | 0 | 0 |
| podinfo | go_mux | true | go_cli, grpc, k8s_gateway_api, k8s_ingress, oas2 | 0 | 0 |
| pokeapi | python_django | true | graphql_operation, hasura, js_cli, k8s_ingress, nginx, oas3, python_cli | 0 | 0 |
| pretalx | python_django | true | oas3, python_cli | 0 | 0 |
| vikunja | go_echo | true | go_cli, go_http, go_huma, oas2 | 0 | 0 |

| Technology | Inputs on matched rows | Both | Document only | Code only | Recall | Agreement |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | Parameters | 44 | 0 | 0 | 100.0% | 100.0% |
| cs_aspnet_core_minimal_api | Body fields | 39 | 0 | 0 | 100.0% | 100.0% |
| go_chi | Parameters | 57 | 1 | 110 | 98.3% | 34.1% |
| go_chi | Body fields | 168 | 10 | 37 | 94.4% | 82.0% |
| go_echo | Parameters | 254 | 16 | 78 | 94.1% | 76.5% |
| go_echo | Body fields | 428 | 169 | 295 | 71.7% | 59.2% |
| go_gin | Parameters | 130 | 11 | 122 | 92.2% | 51.6% |
| go_gin | Body fields | 326 | 16 | 467 | 95.3% | 41.1% |
| go_mux | Parameters | 51 | 97 | 0 | 34.5% | 100.0% |
| go_mux | Body fields | 0 | 92 | 0 | 0.0% | n/a |
| java_spring | Parameters | 544 | 21 | 109 | 96.3% | 83.3% |
| java_spring | Body fields | 378 | 67 | 90 | 84.9% | 80.8% |
| js_express | Parameters | 313 | 35 | 80 | 89.9% | 79.6% |
| js_express | Body fields | 164 | 20 | 79 | 89.1% | 67.5% |
| python_django | Parameters | 609 | 19 | 381 | 97.0% | 61.5% |
| python_django | Body fields | 393 | 60 | 21 | 86.8% | 94.9% |
| python_fastapi | Parameters | 454 | 20 | 9 | 95.8% | 98.1% |
| python_fastapi | Body fields | 363 | 30 | 12 | 92.4% | 96.8% |
| ts_nestjs | Parameters | 312 | 35 | 2 | 89.9% | 99.4% |
| ts_nestjs | Body fields | 492 | 3 | 1 | 99.4% | 99.8% |

| Technology | Both guarded | Both open | Document guarded, code open | Document open, code guarded |
| --- | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 0 | 16 | 0 | 0 |
| go_chi | 120 | 3 | 8 | 133 |
| go_echo | 135 | 81 | 1 | 8 |
| go_gin | 162 | 56 | 10 | 10 |
| go_mux | 0 | 90 | 1 | 0 |
| java_spring | 0 | 0 | 182 | 0 |
| js_express | 8 | 170 | 0 | 233 |
| python_django | 0 | 230 | 0 | 5 |
| python_fastapi | 325 | 17 | 6 | 0 |
| ts_nestjs | 268 | 19 | 0 | 0 |

| Technology | Resolution claim | Marked endpoints | Share of code endpoints |
| --- | --- | ---: | ---: |
| go_chi | `handler:heuristic` | 21 | 4.1% |
| go_echo | `handler:heuristic` | 151 | 33.0% |
| go_echo | `prefix:heuristic` | 1 | 0.2% |
| go_echo | `prefix:unresolved` | 4 | 0.9% |
| go_gin | `handler:heuristic` | 8 | 2.8% |
| go_gin | `prefix:unresolved` | 228 | 80.9% |
| go_mux | `prefix:heuristic` | 108 | 28.6% |
| js_express | `prefix:heuristic` | 217 | 32.1% |
| js_express | `prefix:unresolved` | 11 | 1.6% |
| python_django | `prefix:unresolved` | 1 | 0.2% |
| python_fastapi | `prefix:heuristic` | 21 | 4.5% |

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
- [listmonk](https://github.com/knadh/listmonk/tree/878b5313d51942b722c33d33f9d1be955578d7e3) · `878b5313d51942b722c33d33f9d1be955578d7e3` · `go_echo` · scope `cmd` · `docs/swagger/collections.yaml`. .github/workflows/github-pages.yml renders Swagger UI from this hand-maintained collection. cmd/handlers.go registers both the mailing-list API and subscriber-facing pages. Keep its literal /api prefix. The collection omits GET /api/subscribers/:id/activity and the user-management endpoints.
- [meshery](https://github.com/meshery/meshery/tree/016b42910216f2072b4f6a1527cf3a90f1191c00) · `016b42910216f2072b4f6a1527cf3a90f1191c00` · `go_mux` · scope `server` · `docs/data/openapi.yml`. The Meshery Server contract is bundled from API definitions maintained in meshery/schemas. The contributing-schemas guide describes the OSS bundle. server/router/server.go registers the Gorilla mux routes, including /api/registry and its deprecated /api/meshmodels alias through registerRegistryRoute. The contract includes controller status subscriptions but omits GET /api/system/events/subscribe and the /api/user/prefs routes.
- [owncast](https://github.com/owncast/owncast/tree/c3a9ac1c46c043358fe7382a6d62d5227e4b2efe) · `c3a9ac1c46c043358fe7382a6d62d5227e4b2efe` · `go_chi` · scope `.` · `openapi.yaml`. Makefile api-generate produces the checked-in chi server from this spec; /api is a real mount, not a prefix to strip.
- [podinfo](https://github.com/stefanprodan/podinfo/tree/fd3a834ed8d14b80ea334cf8a2fddd4597924da6) · `fd3a834ed8d14b80ea334cf8a2fddd4597924da6` · `go_mux` · scope `.` · `pkg/api/http/docs/swagger.json`. Makefile swagger regenerates this document from handler annotations; runtime path helpers remain part of the analyzer task. token/validate is annotated POST although registered GET.
- [pokeapi](https://github.com/PokeAPI/pokeapi/tree/8a92bfa7dab2f12b84b5d151562f9857c133ff30) · `8a92bfa7dab2f12b84b5d151562f9857c133ff30` · `python_django` · scope `.` · `openapi.yml`. Makefile openapi-generate uses Django spectacular; describes the REST API, not the separate GraphQL service.
- [pretalx](https://github.com/pretalx/pretalx/tree/1510dea9aafd580d1b2d7b8466736a09cd0298ec) · `1510dea9aafd580d1b2d7b8466736a09cd0298ec` · `python_django` · scope `src/pretalx` · `doc/api/schema.yml`. justfile:125-128 regenerates this committed schema through Django spectacular; src/pretalx/common/management/commands/spectacular.py:9-16 delegates to drf-spectacular. Covers the complete REST API (src/pretalx/urls.py:42 and api/urls.py); the scoped application also contains organiser, agenda and submission UI routes, which remain visible as code-only rows. No prefix adjustment.
- [vikunja](https://github.com/go-vikunja/vikunja/tree/293264397571be437c9bc9a32b4c492bd566dbc2) · `293264397571be437c9bc9a32b4c492bd566dbc2` · `go_echo` · scope `pkg` · `pkg/swagger/swagger.json`. magefile.go Generate.SwaggerDocs runs swag; release automation regenerates and commits pkg/swagger. Only pkg is scanned; standalone example plugins and the frontend are outside this service scope. Known stale annotations: singular image instead of images in the Unsplash proxy; PUT rather than POST for label updates.

<!-- /SCOREBOARD -->

## Runtime route reference

For Express, Hono, FastAPI and Gin, Noir also compares its HTTP endpoints with the framework's registered routes. On these small purpose-written apps, precision is the share of reported method/path pairs in the route table. Recall is the share of registered pairs Noir finds. The scoreboard measures agreement with real repositories’ OpenAPI contracts, where an undocumented route can still be live. The runtime corpus covers selected routing features and cannot estimate accuracy across production applications. It scores registration only. Parameters, guards and implicit dispatch such as HEAD falling back to GET are outside the comparison.

Run `just runtime-reference` to generate the sorted tables and their framework versions and UTC dates. Express records a route-level `.all()` as `_all`, rendered as `ALL`. Hono reports `ALL` and its pass-through middleware is excluded. FastAPI lists the methods supplied to `api_route` and the reference app disables automatic docs. Gin lists each verb registered by `Any`. The comparison preserves these method differences and applies Noir’s placeholder normalization on both sides.

The functional suite scans only each app’s `src/`. A missing `routes.json` makes that example pending. Each app’s `known-gaps.txt` records missed and extra pairs. A new difference fails the spec, and a resolved difference fails until its entry is removed.

## Method

Each entry in [`scripts/scoreboard/corpus.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/corpus.json) contains only its repository pin, code technology, service scope, selected in-tree OpenAPI files, optional `spec_prefix` and `exclude_paths`, and a short note. Exclusions are explicit service boundaries passed to Noir's existing `--exclude-path` option and included in snapshot identity: NodeBB's separate web installer (`install/web.js:63-68`) and Gotify's example plugin (`plugin/example/echo/echo.go:74-77`) are outside their scored services. The runner shallow-fetches the pinned object and exports that service and the selected spec files into scratch space. Other OpenAPI entry documents are removed. Compiled WebAssembly (`*.wasm`) and CSV datasets (`*.csv`) are excluded; neither is route source for a scored analyzer. Scanner errors stop publication. Corpus applications are never built, installed, or run.

The original endpoint series uses a combined scan with the pinned code analyzers forced and the OAS2/OAS3 detectors enabled. The counts use its optimized HTTP rows: **matched** has both the scored code technology and a `spec` contributor in `details.technologies`; **spec-only** lacks the scored code contributor; **code-only** lacks a spec contributor. A singleton contributor comes from `details.technology`. Technology totals sum repository counts before computing ratios.

- **Recall** = matched / (matched + spec-only), the share of documented HTTP operations found by the code analyzer.
- **Agreement** = matched / (matched + code-only), the share of code output also documented. It is a lower bound on precision if matched spec operations are valid, not measured precision. Real undocumented health, admin and UI routes lower it.
- **Marked** counts code endpoints carrying any nonempty `resolution` map once. Each `claim:status` is also counted separately against the same code denominator; claims can overlap. Unmarked does not mean verified correct. This scan runs with taggers and AI context disabled.
- Empty denominators are `null` in results and `n/a` in tables. Only HTTP rows that Noir imports can enter the denominators. Schema types, values, WebSocket operations and runtime reachability are outside these measurements.

### Detection, parameters and guards

**Detection.** An unrestricted scan of the same staged files and exclusions supplies the technology inventory, including detectors that emitted no endpoints. Each repository/technology row records whether Noir detected that pin and lists every detected technology outside the repository’s code pins, including OpenAPI. Forced-only and automatic-only count HTTP rows carrying the scored contributor in just one scan. The comparison uses the method, Noir’s normalized whole-segment placeholders and the contributor’s origin scope. Equal keys retain their multiplicity. The per-repository detection files in `tmp/scoreboard/` list the differing methods, URLs and locations. Technology totals sum the differences and list the union of other technologies. Additional detections can be legitimate.

**Parameters.** Credentials a document declares through its security schemes (an `Authorization` header, an API-key header or cookie) are left out of this comparison on both sides; the guard counts below cover them. For each HTTP row matched by the original combined scan, the runner looks up its independent rows in a code-only scan for that technology and an OAS-only scan. It uses the same method and Noir’s placeholder normalization, then the merged row’s source locations and exact URL to distinguish same-shaped candidates. A missing or ambiguous join stops publication. Each side contributes a set of (location, name) pairs per row. Header names are case-insensitive. Whole-segment path parameters compare by slot in their respective URLs. Other path names, query names and cookie names compare literally, including case. A separate set compares JSON, body and form fields by exact name across encodings. A JSON/body input named `body` supplies no identifiable field and is omitted on either side, including a literal JSON property of that name. Named fields on the other side still count. Noir can infer path parameters from URLs and credentials from security schemes, so these counts describe its imported reports. For each set, recall divides the shared count by the document count, and agreement divides it by the code count, after summing across rows.

**Guards.** The OAS-only scan retains the importer’s `auth` tag from `oas2_access` or `oas3_access`. Operation-level `security` overrides the root declaration. An explicit empty list, an anonymous `{}` alternative or no declaration counts as open. The importer filters unknown schemes when a scheme registry exists. The code-only scan enables `--use-all-taggers` and counts an endpoint as guarded when a framework tagger ending in `_auth` emits the endpoint tag `auth`. Authorization-only and credential parameter tags supply no authentication signal. Each matched row contributes to one of four counts according to those two signals. Open on the code side means Noir found no authentication guard. A stale document or a guard beyond the tagger’s coverage can produce a disagreement.

The current corpus has one code technology per repository. It therefore takes four scans per repository instead of one (68 scans across the 17 pins). Allow roughly four times the scanning time as a planning estimate. Automatic detection and tagging costs depend on the service, and each checkout and export is shared.

### Explicit deployment-prefix adjustment

Supabase Auth declares `spec_prefix: "/auth/v1"`. Its `openapi.yaml:37-38` declares the hosted server URL `https://{project}.supabase.co/auth/v1`. The service itself registers root-local routes: `internal/api/api.go:219-222` opens the `/` router, and `:268` registers `/token`. `internal/api/router.go:17-31` passes these paths directly to chi. The API forwards directly to that router (`api.go:498,520`), and `cmd/serve_cmd.go:63-75` installs the API as the HTTP server handler without an `/auth/v1` mount. So the prefix is a hosted deployment boundary, not a missing source prefix.

Before importing that spec, the runner removes the explicitly declared prefix from its **staged copy's root server URLs**, which makes its spec rows local before Noir joins them. It validates that every declared server path exactly equals the configured prefix, and rejects scoped server overrides. The original checkout and code rows stay unchanged. Spec line numbers for adjusted documents refer to the retained staged copy; code locations refer to the pinned source. No endpoint matcher is added.

Flowable declares `spec_prefix: "/flowable-rest/service"` for its process-controller library. The committed Swagger 2 document declares that `basePath` at line 20. The separate REST application supplies `/flowable-rest` through `modules/flowable-app-rest/src/main/resources/flowable-default.properties:2` and the `/service` servlet path at line 43. `BaseRestApiConfiguration.java:41-48` in the Spring Boot autoconfigure module installs that servlet mapping. These deployment settings are outside the scoped `modules/flowable-rest/src/main` library; its hand-written controllers register local paths (for example, `DeploymentCollectionResource.java:106`). The runner requires an exact Swagger 2 `basePath` match and changes only the staged value to `/`. It does not alter operation paths.

Owncast is different: `webserver/router/router.go:93` mounts the generated API at `/api/`. Its spec's `/api` is in the source and is retained. Only Supabase Auth and Flowable have prefix adjustments. Noir's own normalization still handles placeholder spellings; this recipe adds no case, slash, `ANY`, wildcard, constant-prefix or gateway-rewrite matching. Gateway technologies are excluded because coverage rules are not one-to-one API operations.

### Source-labelled estimates

Each technology contributes at most 25 unmatched rows **across both sides combined**. The sampler shares those slots among repositories and sides, then takes evenly spaced rows from each sorted list. A conditional registration counts as real when the code shows a configuration that serves it. A method the router registers also counts as real when the handler it reaches then rejects that method itself, as the runtime comparison below does: the router dispatches the request. A documented spelling already served by a correctly reported pattern is `covered`. The original join still shows both spellings.

Estimated precision is (matched + estimated real code-only rows) / all reported rows. Estimated recall is matched / (matched + estimated document-only misses and wrong addresses). Each repository projects its decided sample share onto its own unmatched count before the scoreboard sums across repositories. Both estimates assume matched rows are valid. The deterministic sample gives no confidence interval and cannot measure routes absent from both sources. Each estimate includes its decided sample size, unlabelled count and `cannot_tell` count. A nonempty side with no decided sample makes the corresponding estimate unavailable. In the JSON, compare `marked_by_verdict` with each code verdict count to see how often resolution marks identify errors or appear on real routes.

To label a row, open the technology’s `*-audit-sample.json` in the scoreboard artifact. Trace the handler and its mounts in the pinned source. Add one tab-separated line to `scripts/scoreboard/labels.tsv` with the repository, technology, application commit, exact side, method, URL, verdict, relative `file:line` and a sentence of evidence. Use `real`, `false_positive` or `wrong_address` on the code side and `miss`, `not_served`, `covered` or `wrong_address` on the document side. Use `cannot_tell` on either side and record what the source leaves unresolved. A changed pin or sample can leave a label stale. Check the new evidence before updating it.

### Historical source audits

The dated table below records a manual audit of the measured snapshot. The initial audit sampled up to 25 unmatched rows per technology. Slots are allocated across repository/side buckets, then evenly spaced positions are taken within each sorted bucket. These are sample counts, not estimated totals. An operation can appear on both unmatched sides.

Classifications are analyzer miss, analyzer false positive, stale or wrong spec, undocumented route, prefix/method/slash difference that is not an analyzer error, and other. They do not change the ratios. These historical counts predate the checked-in row labels.

<!-- AUDIT -->

Audit date: 2026-11-15. 153 unmatched rows checked against the pinned sources.

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

This audit was taken at analyzer revision `8184cd4`. Two of the misses it found have since been fixed: the FastAPI row's 25 misses were all InvokeAI's dropped `/api` prefix ([#3614](https://github.com/owasp-noir/noir/issues/3614)), and the go_chi miss was supabase/auth's SCIM prefix ([#3616](https://github.com/owasp-noir/noir/issues/3616)). FastAPI's remaining 4 unmatched rows have not been re-audited. Residual slash differences are left visible. All 11 unmatched Express rows were audited.

Expansion audit: 2026-11-15, analyzer revision `54ff7225277f691ac19816faad875c52979e39c0`. Another 137 unmatched rows were checked against the five new pinned repositories; the langflow row was re-audited on 2026-11-16 at `830b4cfce775d24812f4b0305df6fc24359dcdcb`. Each side is sampled separately: all rows if there are at most 25, otherwise 25 evenly spaced rows from the sorted list, at index `floor(i * count / 25)`. The historical table above is retained; it is not a current re-audit of the original corpus. All metric fields for the ten original repositories are unchanged from the committed baseline.

| Repository | Spec-only audited | Code-only audited | Analyzer miss | Analyzer false positive | Stale spec | Undocumented route | Prefix/method/slash | Other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| flowable-engine | 2 | 25 | 0 | 0 | 0 | 24 | 0 | 3 |
| NodeBB | 25 | 25 | 23 | 17 | 1 | 8 | 1 | 0 |
| gotify | 0 | 10 | 0 | 0 | 0 | 10 | 0 | 0 |
| langflow | 0 | 25 | 0 | 0 | 0 | 24 | 0 | 1 |
| pretalx | 0 | 25 | 0 | 0 | 0 | 25 | 0 | 0 |

Flowable's three “other” rows are two documented literal `users` operations and one sampled controller row with `{family}`. `ProcessInstanceIdentityLinkResource.java:49,73,98-100` registers and validates `users` or `groups`; this is a literal-versus-parameter specialization. Its other sampled operations are real registrations absent from the contract. Gotify's sample contains UI/docs, explicit HEAD health and conditional MCP routes. Pretalx's sample contains organiser, agenda and submission UI routes outside its REST contract.

NodeBB passes each route module its mount name as an argument. `src/routes/index.js:236-254` takes the names from a plugin hook whose defaults are `admin`, `user`, `tags` and so on, and modules such as `src/routes/admin.js` build their paths as `/${name}/...`. The spec documents the default names; Noir emits `/api/{name}/...` and `/{name}/...`, so one route shows up on both unmatched sides. This accounts for 23 sampled misses and 16 false positives. One further false positive is the middleware-only `router.all` regex at `index.js:136`; `src/middleware/index.js:130-133` only calls `next()`. The stale row documents the removed read-API session-delete path; `src/routes/write/users.js:66` registers its replacement. The prefix row is `/ping`, whose source prepends configurable `relative_path` (`src/webserver.js:152,191`).

Langflow first matched 4 of its 84 documented operations: routers re-exported through package `__init__.py` files lost `/api/v1` and `/api/v2` ([#3625](https://github.com/owasp-noir/noir/issues/3625)). With that fixed, all 84 match. Of the 25 sampled code-only rows, 24 are routes the project hides from its contract with `include_in_schema=False`, on the router (`api/v1/deployments.py:36`, `models.py:24`, `knowledge_bases.py:35`) or on the route; the other is the static-file mount at `main.py:584`.

<!-- /AUDIT -->

### Re-run and artifacts

```sh
just scoreboard
bash docs/scripts/check_doc_parity.sh
hwaro build -i docs
```

The weekly and manually dispatched scoreboard workflow runs this recipe on the default branch. It uploads the row reports and flags repositories with fewer matches or more document-only rows than the committed snapshot. The recipe uses `build-release` through the compile gate. It needs git, tar, and network access for uncached pins. Checkouts and exports live under `$TMPDIR/noir-codex-scoreboard/` (or `/tmp/noir-codex-scoreboard/`). Per-repository matched/spec-only/code-only lists and per-technology audit samples are written to ignored `tmp/scoreboard/`; they are not committed.

The compact regression snapshot is [`scripts/scoreboard/results.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/results.json). It contains counts, ratios, marks, repository pins, date and analyzer revision. The snapshot date is preserved when analyzer revision and corpus pins are unchanged. Commit analyzer/dependency changes before running; dirty or untracked `src` files and modified shard manifests are rejected. Output is sorted and excludes durations and absolute scratch paths.

Hwaro renders the committed Markdown tables. It does not read the results file at build time, so the file lives with the corpus rather than in `docs/data/`. CI's supported-doc generator does not call this recipe or fetch the corpus. Site builds work offline.

### Candidates not selected

- **spring-petclinic-rest**: method mappings are generated from its spec during build and absent from the checkout, so a 0% score would not be an analyzer failure.
- **juice-shop**: its spec intentionally covers B2B orders only; scoring the entire service made agreement primarily a measure of that limited scope.
- **Earlier Spring replacements**: spring-cloud-dataflow, ThingsBoard and Stirling-PDF had no suitable committed contract in the initial investigation. This expansion admits Flowable's 184-operation process-service Swagger 2 contract instead of its 15-operation decision contract. Its OpenAPI 3 alternatives remain excluded: `docs/public-api/references/openapi/README.md:5-7` explicitly says they are incomplete. The stable Swagger documents are identified as generated from source annotations with manual corrections in `references/swagger/README.md:7-13`; the generator selects the process-controller package at `tools/flowable-oas-generator/pom.xml:51-84`.
- **Second Express candidate**: Directus has a broad contract, but it omits current Access, Policies, Panels, Notifications and Deployment APIs and retains obsolete OAuth/relation paths. It was not added; NodeBB now provides the second Express data point. The RealWorld Express app had no committed OpenAPI document.
- **OWASP/crAPI**: its shared contract spans several services and cannot supply a separate denominator for one code technology.
- **spring-petclinic-microservices**: no checked-in OpenAPI document at the inspected pin.
- **VAmPI**: Connexion constructs routes from the same spec rather than independent Flask declarations.
- **shlink**: left out because the corpus already covered enough technologies, not because its contract is stale.
- **ASP.NET Core minimal APIs** — CleanArchitecture builds `src/Web/wwwroot/openapi/v1.json`. Its two committed NSwag files configure client generation. dotnet-starter-kit serves a document per API version, and TodoApp calls `MapOpenApi()` in `Todo.Api/Program.cs`. None of the three commits its service document.
- **Echo** — Gotenberg registers module routes on Echo, but its contributing guide places the OpenAPI generator and its output in the separate gotenberg.dev repository. Memos commits 92 operations in `proto/gen/openapi.yaml`. Protoc generates them from protobuf definitions served through gRPC-Gateway.
- **Gorilla mux** — Mattermost's Makefile concatenates `api/v4/source/` fragments. The checkout lacks the assembled v4 document. Tyk commits a 66-operation Gateway contract, but `swagger.yml` references a schema on the remote master branch. Noir reports an incomplete import, which stops the scoreboard.
- **Nakadi** — Its hand-maintained contract is suitable, and 43 routes agree by method and path. The multi-module Gradle build places the document and controllers in different projects, so the scoreboard cannot pair their rows under its merged-row matching rule.
- **Spring** — Halo's CI regenerates the 410-operation `aggregated.json` from Spring WebFlux. `SwaggerConfig.java` selects v1alpha1 API paths and specific login and setup paths. Apollo's portal generates Spring interfaces from a versioned document in the separate apollo-openapi repository.
- **NestJS** — NocoDB's versioned schemas include licensed operations, such as v3 scripts and dashboards, whose controllers are absent from the community checkout. Its per-base Swagger endpoint describes a single database. Ghostfolio documents selected public routes in its README. Amplication creates Swagger documents from running NestJS services. Neither commits a service contract.

Also inspected for this expansion and not added: apache/fineract (JAX-RS `@Path` resources, not Spring mappings); novuhq/novu (its export removes endpoints without API-key authentication); thomiceli/opengist (the document covers only the token API and nothing checks it against the routes); dyrector-io/dyrectorio (the Swagger configuration is committed, the generated document is not); and PrefectHQ/prefect, freqtrade/freqtrade, healthchecks/healthchecks, PostHog/posthog, wger-project/wger and statping-ng/statping-ng (no committed service OpenAPI document). Langflow is pinned to the commit that introduced its schema generator: at its current head the workflow routes come from the separate `lfx` package, outside the scanned scope. The pin was chosen before its score was seen and does not measure current Langflow.
