+++
title = "API agreement scoreboard"
description = "Code analyzer recall and agreement against pinned repositories' own API specifications."
weight = 2
+++

This source-only measurement compares code analyzers with the OpenAPI contracts kept in real repositories. Fixtures are not ground truth. The corpus is small and selected for inspectable contracts; its numbers do not represent all projects using a framework.

<!-- SCOREBOARD -->

Measured: 2026-11-15. Analyzer source: `863ed43426e3d9ada373034088a3915100d142a9`.

A technology measured on one repository is a single data point.

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

## Method

Each entry in [`scripts/scoreboard/corpus.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/corpus.json) contains only its repository pin, code technology, service scope, selected in-tree OpenAPI files, optional `spec_prefix`, and a short note. The runner shallow-fetches the pinned object and exports that service and the selected spec files into scratch space. Other OpenAPI entry documents are removed. Compiled WebAssembly (`*.wasm`) and CSV datasets (`*.csv`) are excluded; neither is route source for a scored analyzer. Scanner errors stop publication. Corpus applications are never built, installed, or run.

One Noir scan reads code and OpenAPI together. The counts use its optimized HTTP rows: **matched** has both the scored code technology and a `spec` contributor in `details.technologies`; **spec-only** lacks the scored code contributor; **code-only** lacks a spec contributor. A singleton contributor comes from `details.technology`. Technology totals sum repository counts before computing ratios.

- **Recall** = matched / (matched + spec-only), the share of documented HTTP operations found by the code analyzer.
- **Agreement** = matched / (matched + code-only), the share of code output also documented. It is a lower bound on precision if matched spec operations are valid, not measured precision. Real undocumented health, admin and UI routes lower it.
- **Marked** counts code endpoints carrying any nonempty `resolution` map once. Each `claim:status` is also counted separately against the same code denominator; claims can overlap. Unmarked does not mean verified correct. Optional AI context and taggers are not enabled.
- Empty denominators are `null` in results and `n/a` in tables. Parameters, schemas, authentication, WebSockets and runtime reachability are not scored. Spec operations Noir cannot import are outside the denominator.

### Explicit deployment-prefix adjustment

Only Supabase Auth declares `spec_prefix: "/auth/v1"`. Its `openapi.yaml:37-38` declares the hosted server URL `https://{project}.supabase.co/auth/v1`. The service itself registers root-local routes: `internal/api/api.go:219-222` opens the `/` router, and `:268` registers `/token`. `internal/api/router.go:17-31` passes these paths directly to chi. The API forwards directly to that router (`api.go:498,520`), and `cmd/serve_cmd.go:63-75` installs the API as the HTTP server handler without an `/auth/v1` mount. So the prefix is a hosted deployment boundary, not a missing source prefix.

Before importing that spec, the runner removes the explicitly declared prefix from its **staged copy's root server URLs**, which makes its spec rows local before Noir joins them. It validates that every declared server path exactly equals the configured prefix, and rejects scoped server overrides. The original checkout and code rows stay unchanged. Spec line numbers for adjusted documents refer to the retained staged copy; code locations refer to the pinned source. No endpoint matcher is added.

Owncast is different: `webserver/router/router.go:93` mounts the generated API at `/api/`. Its spec's `/api` is in the source and is retained. No other entry has a prefix adjustment. Noir's own normalization still handles placeholder spellings; this recipe adds no case, slash, `ANY`, wildcard, constant-prefix or gateway-rewrite matching. Gateway technologies are excluded because coverage rules are not one-to-one API operations.

### Source audit

The dated table below records a manual audit of the measured snapshot. For each technology, all unmatched rows are checked when there are at most 25; otherwise 25 are sampled. Slots are allocated across repository/side buckets, then evenly spaced positions are taken within each sorted bucket. These are sample counts, not estimated totals. An operation can appear on both unmatched sides.

Classifications are analyzer miss, stale spec, undocumented route, prefix/method mismatch that is not an analyzer error, and other. They do not change the ratios. Per-row evidence is not committed. Re-audit changed rows and update this dated table before publishing a new measurement; the recipe regenerates metrics, not the manual audit.

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

<!-- /AUDIT -->

### Re-run and artifacts

```sh
just scoreboard
bash docs/scripts/check_doc_parity.sh
hwaro build -i docs
```

The recipe is on demand and depends on `build-release`, through the compile gate. It needs git, tar, and network access for uncached pins. Checkouts and exports live under `$TMPDIR/noir-codex-scoreboard/` (or `/tmp/noir-codex-scoreboard/`). Per-repository matched/spec-only/code-only lists and per-technology audit samples are written to ignored `tmp/scoreboard/`; they are not committed.

The compact regression snapshot is [`scripts/scoreboard/results.json`](https://github.com/owasp-noir/noir/blob/main/scripts/scoreboard/results.json). It contains counts, ratios, marks, repository pins, date and analyzer revision. The snapshot date is preserved when analyzer revision and corpus pins are unchanged. Commit analyzer/dependency changes before running; dirty or untracked `src` files and modified shard manifests are rejected. Output is sorted and excludes durations and absolute scratch paths.

Hwaro renders the committed Markdown tables. It does not read the results file at build time, so the file lives with the corpus rather than in `docs/data/`. CI's supported-doc generator does not call this recipe or fetch the corpus. Site builds work offline.

### Candidates not selected

- **spring-petclinic-rest**: method mappings are generated from its spec during build and absent from the checkout, so a 0% score would not be an analyzer failure.
- **juice-shop**: its spec intentionally covers B2B orders only; scoring the entire service made agreement primarily a measure of that limited scope.
- **Spring replacements**: spring-cloud-dataflow, ThingsBoard and Stirling-PDF had no suitable committed contract. Flowable has hand-written controllers and generated specs, but its decision contract also requires separate deployment/version validation. Spring is left unmeasured rather than given a misleading row.
- **Second Express candidate**: Directus has a broad contract, but it omits current Access, Policies, Panels, Notifications and Deployment APIs and retains obsolete OAuth/relation paths. It was not added; DVWS remains a single Express data point. The RealWorld Express app had no committed OpenAPI document.
- **OWASP/crAPI**: its shared contract spans several services and cannot supply a separate denominator for one code technology.
- **spring-petclinic-microservices**: no checked-in OpenAPI document at the inspected pin.
- **VAmPI**: Connexion constructs routes from the same spec rather than independent Flask declarations.
- **shlink**: left out because the corpus already covered enough technologies, not because its contract is stale.
