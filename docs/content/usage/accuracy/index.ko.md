+++
title = "API 일치도 스코어보드"
description = "고정된 공개 저장소의 API 명세와 코드 분석 결과를 비교한 재현율과 일치도입니다."
weight = 2
+++

실제 저장소에 포함된 OpenAPI 계약과 코드 분석 결과를 소스만 읽어 비교합니다. 테스트 픽스처를 정답으로 사용하지 않습니다. 확인 가능한 계약을 가진 작은 코퍼스이므로 이 수치를 그 프레임워크의 모든 프로젝트에 일반화할 수 없습니다. 아래 표의 기술 식별자와 저장소 메타데이터는 원문을 유지합니다.

<!-- SCOREBOARD -->

Measured: 2026-11-15. Analyzer source: `863ed43426e3d9ada373034088a3915100d142a9`.

저장소 하나에서 측정한 기술은 단일 데이터 포인트입니다.

| Technology | Repositories | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cs_aspnet_core_minimal_api | 1 | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| go_chi | 2 | 264 | 41 | 249 | 86.6% | 51.5% | 262 (51.1%) |
| go_echo | 1 | 149 | 23 | 115 | 86.6% | 56.4% | 4 (1.5%) |
| go_gin | 1 | 196 | 3 | 34 | 98.5% | 85.2% | 228 (99.1%) |
| go_mux | 1 | 26 | 1 | 60 | 96.3% | 30.2% | 0 (0.0%) |
| js_express | 1 | 53 | 0 | 11 | 100.0% | 82.8% | 0 (0.0%) |
| python_django | 1 | 102 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| python_fastapi | 1 | 264 | 1 | 3 | 99.6% | 98.9% | 0 (0.0%) |
| ts_nestjs | 1 | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |

| Repository | Matched | Spec-only | Code-only | Recall | Agreement | Marked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| InvokeAI | 264 | 1 | 3 | 99.6% | 98.9% | 0 (0.0%) |
| answer | 196 | 3 | 34 | 98.5% | 85.2% | 228 (99.1%) |
| auth | 23 | 41 | 60 | 35.9% | 27.7% | 0 (0.0%) |
| dvws-node | 53 | 0 | 11 | 100.0% | 82.8% | 0 (0.0%) |
| eShop | 16 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| immich | 287 | 0 | 17 | 100.0% | 94.4% | 0 (0.0%) |
| owncast | 241 | 0 | 189 | 100.0% | 56.0% | 262 (60.9%) |
| podinfo | 26 | 1 | 60 | 96.3% | 30.2% | 0 (0.0%) |
| pokeapi | 102 | 0 | 0 | 100.0% | 100.0% | 0 (0.0%) |
| vikunja | 149 | 23 | 115 | 86.6% | 56.4% | 4 (1.5%) |

| Technology | Resolution claim | Marked endpoints | Share of code endpoints |
| --- | --- | ---: | ---: |
| go_chi | `handler:heuristic` | 21 | 4.1% |
| go_chi | `prefix:unresolved` | 241 | 47.0% |
| go_echo | `prefix:unresolved` | 4 | 1.5% |
| go_gin | `handler:heuristic` | 6 | 2.6% |
| go_gin | `prefix:unresolved` | 228 | 99.1% |

- [InvokeAI](https://github.com/invoke-ai/InvokeAI/tree/9264acf9e542d51a21467013029b755686dee375) · `9264acf9e542d51a21467013029b755686dee375` · `python_fastapi` · scope `invokeai/app` · `invokeai/frontend/api/openapi.json`. openapi-checks.yml regenerates the schema from FastAPI and diffs it. Only invokeai/app is scanned; frontend and other packages are excluded.
- [answer](https://github.com/apache/answer/tree/6744295fa888e0621fc9f9a8ace04f1a4daf8554) · `6744295fa888e0621fc9f9a8ace04f1a4daf8554` · `go_gin` · scope `.` · `docs/swagger.json`. Makefile generate runs go generate; swag annotations live on the handlers for this Gin service. Known stale annotations: personal question page lacks its service prefix; activation uses plural users instead of user; notification config documents POST instead of GET.
- [auth](https://github.com/supabase/auth/tree/3e79d8513b67d7dc3f234153aacc074daf82db5f) · `3e79d8513b67d7dc3f234153aacc074daf82db5f` · `go_chi` · scope `.` · `openapi.yaml`. Maintained beside internal/api; the hosted prefix is declared at openapi.yaml:38 and absent from the root-local router (api.go:219-222,498,520). Reauthenticate has a stale documented verb. Spec rows are compared without the hosted `/auth/v1` prefix.
- [dvws-node](https://github.com/snoopysecurity/dvws-node/tree/4221c04f132960a0ccca4bf5aa5f3a9f53172778) · `4221c04f132960a0ccca4bf5aa5f3a9f53172778` · `js_express` · scope `.` · `docs/openapi/openapi.json`. scripts/generate-openapi.js generates this contract with swagger-autogen from src/routes; test/openapi.test.js checks the document.
- [eShop](https://github.com/dotnet/eShop/tree/913acea66708a59595351174cee9b29f37179d29) · `913acea66708a59595351174cee9b29f37179d29` · `cs_aspnet_core_minimal_api` · scope `src/Catalog.API` · `src/Catalog.API/Catalog.API.json`, `src/Catalog.API/Catalog.API_v2.json`. Catalog.API.csproj exports OpenAPI during build with Microsoft.Extensions.ApiDescription.Server. Both API versions are included; query-parameter version distinctions are outside endpoint scoring. Only Catalog.API source is scanned, not other services or shared default endpoints.
- [immich](https://github.com/immich-app/immich/tree/e5d6eb7be67834f59d90e4b7a86f5dec7ac9af86) · `e5d6eb7be67834f59d90e4b7a86f5dec7ac9af86` · `ts_nestjs` · scope `server` · `open-api/immich-openapi-specs.json`. Generated from server controllers by the OpenAPI tooling; .github/workflows/check-openapi.yml checks contract changes. Only server is scanned.
- [owncast](https://github.com/owncast/owncast/tree/c3a9ac1c46c043358fe7382a6d62d5227e4b2efe) · `c3a9ac1c46c043358fe7382a6d62d5227e4b2efe` · `go_chi` · scope `.` · `openapi.yaml`. Makefile api-generate produces the checked-in chi server from this spec; /api is a real mount, not a prefix to strip.
- [podinfo](https://github.com/stefanprodan/podinfo/tree/fd3a834ed8d14b80ea334cf8a2fddd4597924da6) · `fd3a834ed8d14b80ea334cf8a2fddd4597924da6` · `go_mux` · scope `.` · `pkg/api/http/docs/swagger.json`. Makefile swagger regenerates this document from handler annotations; runtime path helpers remain part of the analyzer task. token/validate is annotated POST although registered GET.
- [pokeapi](https://github.com/PokeAPI/pokeapi/tree/8a92bfa7dab2f12b84b5d151562f9857c133ff30) · `8a92bfa7dab2f12b84b5d151562f9857c133ff30` · `python_django` · scope `.` · `openapi.yml`. Makefile openapi-generate uses Django spectacular; describes the REST API, not the separate GraphQL service.
- [vikunja](https://github.com/go-vikunja/vikunja/tree/293264397571be437c9bc9a32b4c492bd566dbc2) · `293264397571be437c9bc9a32b4c492bd566dbc2` · `go_echo` · scope `pkg` · `pkg/swagger/swagger.json`. magefile.go Generate.SwaggerDocs runs swag; release automation regenerates and commits pkg/swagger. Only pkg is scanned; standalone example plugins and the frontend are outside this service scope. Known stale annotations: singular image instead of images in the Unsplash proxy; PUT rather than POST for label updates.

<!-- /SCOREBOARD -->

## 측정 방법

[`scripts/scoreboard/corpus.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/corpus.json)에는 저장소 커밋, 코드 기술, 서비스 범위, 선택한 OpenAPI 파일, 선택적 `spec_prefix`, 짧은 설명만 저장합니다. 실행기는 고정된 커밋을 얕게 가져와 그 서비스와 선택한 명세 파일을 임시 공간에 내보냅니다. 다른 OpenAPI 진입 문서는 제거합니다. 평가 대상 분석기의 경로 소스가 아닌 WebAssembly(`*.wasm`)와 CSV 데이터셋(`*.csv`)은 제외합니다. 스캔 오류가 있으면 게시용 파일 생성을 중단합니다. 코퍼스 애플리케이션은 빌드하거나 설치하거나 실행하지 않습니다.

한 번의 Noir 스캔에서 코드와 OpenAPI를 함께 읽습니다. 최적화된 HTTP 행의 `details.technologies`에 평가 대상 코드 기술과 `spec` 기여자가 함께 있으면 **matched**, 코드 기여자만 없으면 **spec-only**, 명세 기여자만 없으면 **code-only**입니다. 단일 기여자는 `details.technology`에서 읽습니다. 기술별 비율은 저장소별 개수를 합산한 뒤 계산합니다.

- **Recall(재현율)** = matched / (matched + spec-only). 문서의 HTTP 동작 중 코드 분석기가 찾은 비율입니다.
- **Agreement(일치도)** = matched / (matched + code-only). 코드 출력 중 명세에도 있는 비율입니다. 일치한 명세 동작이 유효하다는 전제에서 정밀도의 하한이며, 측정된 정밀도는 아닙니다. 실제로 존재하지만 문서화되지 않은 health, admin, UI 경로도 이 값을 낮춥니다.
- **Marked(표시된 행)**는 비어 있지 않은 `resolution` 맵이 있는 코드 엔드포인트를 한 번씩 셉니다. 각 `claim:status`도 같은 코드 분모로 별도 집계하므로 서로 겹칠 수 있습니다. 표시가 없다고 정확성을 보장하지 않습니다. 선택적 AI 컨텍스트와 태거는 활성화하지 않습니다.
- 분모가 0이면 결과는 `null`, 표는 `n/a`입니다. 파라미터, 스키마, 인증, WebSocket, 실제 실행 시 접근 가능성은 평가하지 않습니다. Noir가 가져오지 못하는 명세 동작은 분모에 포함되지 않습니다.

### 명시적인 배포 접두사 보정

Supabase Auth만 `spec_prefix: "/auth/v1"`을 선언합니다. `openapi.yaml:37-38`은 호스팅 서버 URL을 `https://{project}.supabase.co/auth/v1`로 지정합니다. 서비스는 로컬 경로를 등록합니다. `internal/api/api.go:219-222`는 `/` 라우터를 열고 `:268`은 `/token`을 등록합니다. `internal/api/router.go:17-31`은 경로를 그대로 chi에 넘깁니다. API는 이 라우터에 직접 전달하고(`api.go:498,520`), `cmd/serve_cmd.go:63-75`는 `/auth/v1` 마운트 없이 API를 HTTP 서버 핸들러로 설치합니다. 따라서 이 접두사는 소스에서 누락된 경로가 아닌 호스팅 배포 경계입니다.

실행기는 이 명세를 가져오기 전에 **임시 복사본의 루트 서버 URL**에서 명시된 접두사만 제거합니다. 그러면 Noir가 자체 병합을 하기 전에 명세 행이 로컬 경로가 됩니다. 선언된 모든 서버 경로가 설정한 접두사와 정확히 같은지 검사하며 경로·동작별 서버 재정의가 있으면 거부합니다. 원본 체크아웃과 코드 행은 바꾸지 않고 별도 엔드포인트 매처도 추가하지 않습니다. 보정한 명세의 행 번호는 임시 복사본을 가리키며, 코드 위치는 고정된 원본 소스를 가리킵니다.

Owncast는 다릅니다. `webserver/router/router.go:93`은 생성된 API를 `/api/`에 마운트합니다. 명세의 `/api`는 소스에도 있으므로 유지합니다. 다른 항목에는 접두사 보정이 없습니다. 파라미터 표기는 Noir 자체 정규화를 사용하며 대소문자, 끝 슬래시, `ANY`, 와일드카드, 상수 접두사, 게이트웨이 재작성 매칭을 추가하지 않습니다. 게이트웨이 규칙은 API 동작과 일대일로 대응하지 않아 제외합니다.

### 소스 감사

아래 날짜가 있는 표는 측정 스냅샷에 대한 수동 감사입니다. 기술별 불일치가 25개 이하면 전부, 더 많으면 25개를 확인합니다. 저장소와 spec-only/code-only 조합에 표본 수를 배분하고 정렬된 목록에서 일정 간격으로 선택합니다. 전체 오류 추정치가 아닌 표본 개수이며, 같은 동작이 양쪽 불일치에 포함될 수 있습니다.

분류는 분석기 누락, 오래된 명세, 문서화되지 않은 경로, 분석기 오류가 아닌 접두사·메서드 차이, 기타입니다. 분류는 비율을 바꾸지 않습니다. 행별 근거는 커밋하지 않습니다. 새 측정을 게시하기 전에 바뀐 행을 다시 확인하고 이 날짜가 있는 표를 갱신해야 합니다. 레시피는 측정값만 생성하며 수동 감사를 재생성하지 않습니다.

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
- **Spring 대체 후보**: spring-cloud-dataflow, ThingsBoard, Stirling-PDF에는 적합한 커밋된 계약이 없었습니다. Flowable에는 직접 작성한 컨트롤러와 생성된 명세가 있지만 decision 계약의 배포·버전 범위를 별도로 검증해야 합니다. 오해를 부를 행을 넣는 대신 Spring은 측정하지 않은 채로 둡니다.
- **두 번째 Express 후보**: Directus의 계약은 넓은 범위를 다루지만 현재 Access, Policies, Panels, Notifications, Deployment API가 없고 오래된 OAuth·관계 경로가 남아 있습니다. 추가하지 않았으며 DVWS가 단일 Express 데이터 포인트로 남습니다. RealWorld Express 앱에는 커밋된 OpenAPI 문서가 없었습니다.
- **OWASP/crAPI**: 공유 명세가 여러 서비스에 걸쳐 있어 한 코드 기술의 별도 분모로 쓸 수 없습니다.
- **spring-petclinic-microservices**: 확인한 커밋에 OpenAPI 문서가 없습니다.
- **VAmPI**: 독립적인 Flask 선언 대신 같은 명세로 Connexion이 경로를 생성합니다.
- **shlink**: 코퍼스가 이미 충분한 기술을 다뤄서 넣지 않았습니다. 명세가 오래됐기 때문은 아닙니다.
