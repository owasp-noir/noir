+++
title = "AI 컨텍스트"
description = "guards, callees, sources, sinks, validators, signals를 모아 엔드포인트별로 제공하는 AI 리뷰 컨텍스트입니다."
weight = 5
sort_by = "weight"

+++

Noir는 각 엔드포인트에 구조화된 AI 리뷰 컨텍스트를 붙일 수 있습니다. LLM 기반 SAST 도구, 코드 리뷰어, 보안 에이전트가 라우트를 검토할 때 필요한 정적 신호를 한곳에 모아 주므로, 저장소를 직접 훑지 않아도 됩니다.

`--ai-context`로 켭니다.

```bash
noir scan . --ai-context
```

버킷 이름을 쉼표로 구분해 넘기면 필요한 카테고리만 남습니다. 필터가 데이터 자체에 적용되므로 JSON, SARIF, YAML, Postman, OAS 출력도 plain 출력과 같은 선택을 따릅니다.

```bash
noir scan . --ai-context=guards,sinks       # auth + sink, 연결된 시그널 포함
noir scan . --ai-context=callee             # 1-hop handler callee만
noir scan . --ai-context=all                # "전부"의 명시적 형태
noir scan . --ai-context                    # bare 형태, 동일하게 "전부"
```

쓸 수 있는 이름: `guards`, `callee`, `sources`, `sinks`, `validators`, `signals`(그리고 `all`). 대소문자는 구분하지 않습니다.

파생 시그널은 근거 버킷과 연결된 채로 남습니다. `signals`를 선택하면 그
시그널에 필요한 증거(예: `ssrf` → `outbound_http` sink)가 함께 유지되고,
증거 버킷만 선택하면 그에 연결된 시그널만 남습니다(예: `guards,sinks`에도
`authz_absence`가 남음). 이렇게 남은 시그널은 자기 근거도 함께 가져오므로
`guards,sinks`를 골라도 `sources`가 나올 수 있습니다. 여러 버킷을 묶어 판단하는 `priority_review`는
선택에 `signals`가 있을 때만 나옵니다(인자 없는 `--ai-context`와 `all`에는
포함됩니다).

plain 출력에서는 컨텍스트가 있는 엔드포인트마다 `ai_context:` 블록이 붙습니다. 구조화된 출력 형식에서는 같은 구조가 다음 위치에 들어갑니다.

| 출력 형식 | AI 컨텍스트 위치 |
|---|---|
| JSON / JSONL / YAML / TOML | `endpoints[].ai_context` |
| OpenAPI 2.0 / 3.0 | 오퍼레이션 단위 `x-noir-ai-context` 확장 |
| SARIF | `result.properties.noir.ai_context` |
| Postman | 아이템 설명 뒤에 덧붙임 |
| cURL / HTTPie / PowerShell / only-url / only-param | 본래 출력이 바뀌지 않도록 일부러 넣지 않음 |

## 무엇이 들어가나

각 버킷은 `kind`, `name`, 선택적인 `source`, `description`, `path`, `line`, `confidence`, `snippet`을 가진 항목 배열입니다. 버킷은 다음과 같습니다.

| 버킷 | 의미 |
|---|---|
| `guards` | 라우트에 감지된 인증/인가 게이트(미들웨어, 데코레이터, `requires_auth`, 역할 체크 등) |
| `callees` | `--include callee`로 모으는 1-hop 핸들러 callee. 한곳에서 볼 수 있도록 AI 컨텍스트 안에도 다시 넣습니다 |
| `sources` | 핸들러에 도달하는 공격자 제어 입력. 요청 파라미터·헤더·쿠키·GraphQL 필드와 모바일 딥링크 페이로드가 여기 들어갑니다. 검토할 만한 서버 측 값 출처(Spring `@Value` 시크릿, WebSocket CORS 정책 등)도 함께 기록됩니다 |
| `sinks` | 핸들러 본문이나 callee 이름에서 추론된 위험 가능 동작(SQL, 명령 실행, 역직렬화, 템플릿 렌더링, 파일 I/O, 리다이렉트 등) |
| `validators` | 입력 검증/정제 신호(스키마 검증기, 파라미터 형 변환, 허용 목록 패턴). sink 위험을 줄여 주는 단서 |
| `signals` | 그 외 라우트 형태 힌트(가드 없는 상태 변경 메서드, object-level 인가 점검이 필요한 path-id 사용, 파일 업로드 동작 등) |

버킷마다 나올 수 있는 kind는 [버킷별 kind](#버킷별-kind)에 정리했습니다.

목록은 찾을 수 있는 만큼 찾은 결과입니다. 항목마다 휴리스틱 신뢰도가 있어서 받는 쪽에서 기준값으로 거를 수 있습니다. 출력이 너무 커지지 않도록 버킷당 최대 16개 항목만 남깁니다.

비어 있지 않은 컨텍스트에는 `"untrusted_fields": ["name", "path", "snippet"]`도 함께 들어갑니다. 이 필드는 스캔한 저장소에서 그대로 가져온 값이라, `snippet`에는 그 코드를 작성한 쪽의 주석과 문자열 리터럴이 포함됩니다. 이 출력을 LLM에 넘길 때는 이 필드를 신뢰할 수 없는 데이터로 다루고 지시문과 분리하세요.

이 구조는 JSON Schema로 [`schemas/ai-context.schema.json`](https://owasp-noir.github.io/noir/schemas/ai-context.schema.json)에 공개되어 있어, 검증기나 안정적인 형식이 필요한 프롬프트에서 그대로 쓸 수 있습니다. 신뢰할 수 없는 필드에는 `"x-noir-untrusted": true`가 붙어 있습니다. 항목의 `kind` 값은 열린 어휘라서 새 값이 추가되어도 스키마는 바뀌지 않습니다.

## 항목 읽는 법

Phoenix 앱의 엔드포인트 하나를 `--ai-context=guards,sinks`로 좁힌 결과입니다. 뒤쪽 스니펫은 줄였습니다.

```text
DELETE /settings/keys/:id
  ○ path: id
  ○ tags: idor auth
  ○ ai_context:
    - guards:
      * auth_guard: Phoenix :account pipeline [elixir_auth] (./lib/app_web/router.ex:36) (conf 86) - Protected by Phoenix :account pipeline :: 34: pipe_through [:browser, :account] | 36: delete "/keys/:id", PageController, :delete_key | 37: end
    - sources:
      * request_input: path.id [param] (./lib/app_web/router.ex:36) (conf 88) - Route path parameter supplied by the caller. :: ...
    - sinks:
      * redirect: redirect [callee] (./lib/app_web/controllers/page_controller.ex:43) (conf 74) - Potential redirect sink inferred from code or callee name :: ...
    - signals:
      * authz_absence: /settings/keys/:id [heuristic] (./lib/app_web/router.ex:36) (conf 44) - Authenticated endpoint uses a path identifier with no authorization check detected; review for horizontal / vertical privilege escalation. :: ...
```

한 줄의 형식은 `kind: name [source] (path:line) (conf N) - description :: snippet`입니다. `authz_absence` 시그널은 `guards`에 연결되어 있어서 따라 나왔고, 자기 근거인 `sources`도 함께 가져왔습니다. 같은 가드를 JSON으로 보면 이렇습니다.

```json
{
  "kind": "auth_guard",
  "name": "Phoenix :account pipeline",
  "source": "elixir_auth",
  "description": "Protected by Phoenix :account pipeline",
  "path": "./lib/app_web/router.ex",
  "line": 36,
  "confidence": 86,
  "snippet": "34: pipe_through [:browser, :account] | 36: delete \"/keys/:id\", PageController, :delete_key | 37: end"
}
```

| 필드 | 내용 |
|---|---|
| `kind` | 항목의 종류. 버킷별 종류는 아래 표에 있습니다 |
| `name` | 구체적인 대상. callee 표현식, `<type>.<name>` 형태의 파라미터(`query.id`, `json.password`), 가드 이름, 라우트 등 |
| `source` | Noir가 이 항목을 찾은 경로(아래 참고) |
| `description` | 왜 살펴볼 만한지 한 문장으로 적은 설명 |
| `path`, `line` | 근거의 위치. callee는 호출 지점, 가드는 그것을 선언한 미들웨어나 어노테이션, 나머지는 대부분 라우트를 가리킵니다 |
| `confidence` | 0부터 100. 휴리스틱끼리의 상대적인 순위이며 확률이 아닙니다 |
| `snippet` | `line` 주변 소스 몇 줄. 줄 번호를 붙여 ` \| `로 잇고 약 240자에서 자릅니다 |

`source` 값은 다음 중 하나입니다.

| `source` | 의미 |
|---|---|
| `route`, `detector` | 라우트 자체, 그리고 그 라우트를 보고한 기술 |
| `param` | 분석기가 추출한 파라미터에서 읽음 |
| `param_tagger:<tagger>` | 태거가 파라미터에 붙인 태그(`param_tagger:Hunt`) |
| `callee` | 1-hop callee의 이름이나 그 호출 줄에서 매칭 |
| `route_source` | 라우트 근처 핸들러 소스 텍스트에서 매칭 |
| `heuristic` | 같은 컨텍스트의 다른 항목에서 파생 |
| `http_method`, `realtime_method` | HTTP 메서드, 또는 WebSocket 메시지 핸들러에서 읽음 |
| `mobile_deep_link` | 모바일 딥링크나 외부에 공개된 컴포넌트 |
| `endpoint`, `resolver` | 아웃바운드 클라이언트 선언, 그리고 오퍼레이션에 연결된 GraphQL 리졸버 |
| 태거나 분석기 이름 | 해당 태거(`Admin`, `spring_auth`, `go_security`)나 분석기(`nginx_analyzer`, `odoo_analyzer`)가 붙인 태그 |

`--ai-context`를 켜면 callee 수집이 켜지고 모든 태거가 실행됩니다. 둘 다 컨텍스트의 재료이기 때문입니다. `--use-taggers`로 태거를 지정하면 지정한 것만 실행됩니다.

## 버킷별 kind

현재 Noir가 내보내는 kind입니다.

### guards

| Kind | 의미 |
|---|---|
| `auth_guard` | 인증. 호출자가 누구인지 확인합니다(로그인 필수, 세션 확인, JWT나 API 키 검증) |
| `authz_guard` | 인가. 호출자가 무엇을 할 수 있는지 확인합니다(역할, 권한, 정책, 소유자 비교) |
| `csrf_guard` | CSRF 보호. 토큰 검사, `protect_from_forgery`, `SameSite=Strict` |
| `rate_limit_guard` | 스로틀링이나 rate limit 계층 |

가드가 이 버킷에 들어오는 길은 세 가지입니다. 먼저 [프레임워크별 인증 태거](@/usage/more_features/tagger/index.ko.md)가 프레임워크 고유의 장치(Spring Security 체인, Phoenix 파이프라인, Express 미들웨어, Noir가 본문까지 확인한 Go 미들웨어)를 읽어 `auth_guard`나 `authz_guard`를 보고합니다. 이때 `source`는 태거 이름이고 신뢰도는 86입니다. 다른 하나는 핸들러 소스의 이름 매칭(`login_required`, `@PreAuthorize`, `before_action :authenticate_user!`)으로, `source`는 `route_source`이고 신뢰도는 44에서 58 사이입니다. 마지막으로 핸들러가 호출자를 직접 확인하는 함수(`validateSession(req, res)`, `principal.validate_admin_session()`, `validateJobAccess`)를 부르면, 본문 어디에서 부르든 `source`가 `callee`인 가드로 보고합니다. 두 이름 매칭은 태거가 채우지 못한 kind만 채우며, `csrf_guard`와 `rate_limit_guard`는 핸들러 소스의 이름 매칭으로만 나옵니다.

프레임워크가 익명 호출을 허용한다고 명시한 라우트(tRPC `publicProcedure`, Micronaut `@Secured(IS_ANONYMOUS)`)에는 `anonymous` 시그널이 붙고, `auth_guard`와 `authz_guard`의 이름 매칭은 건너뜁니다.

### callees

kind는 `callee` 하나입니다. 핸들러 본문에서 직접 호출하는 함수이며, `name`은 호출 표현식(`App.Keys.delete`), `path:line`은 호출 지점입니다. callee를 보고하는 프레임워크는 [Callee 커버리지](@/usage/supported/callee_coverage/index.ko.md)에 있습니다.

### sources

| Kind | 의미 |
|---|---|
| `request_input` | 호출자가 제어하는 값. 파라미터마다 하나씩 `<type>.<name>` 이름으로 나오며, type은 `path`, `query`, `header`, `cookie`, `json`, `form`, `file`, `xml`입니다. GraphQL 선택 필드는 `graphql.field.<name>`, 모바일 진입점은 `deep_link.mobile_scheme`, `deep_link.universal_link`, `deep_link.android_intent`, `ipc.content_provider`입니다. 쿠키 파라미터가 추출되지 않았는데 핸들러가 쿠키를 직접 읽으면 `route_source`에서 `cookie.<name>`으로 나옵니다 |
| `server_secret_source` | 핸들러가 반환하는 Spring `@Value` 시크릿 |
| `cors_policy` | Spring WebSocket/STOMP 엔드포인트에 등록된 CORS 정책 |

### sinks

| Kind | 의미 |
|---|---|
| `sql` | SQL 호출. raw SQL, DB 계열 리시버의 `execute` / `query`, Spring Data 리포지토리 메서드 |
| `data_store_query` | 문서 저장소나 그래프 저장소 질의(`mongo.query`, Neo4j 클라이언트) |
| `command_exec` | OS 명령 실행. `exec`, `system`, `spawn`, `popen`, `subprocess`, `ProcessBuilder` |
| `code_eval` | 프로세스 내부 코드 평가. `eval`, `new Function`, `instance_eval`, `ScriptEngine` |
| `deserialization` | 안전하지 않은 역직렬화. `pickle.loads`, `yaml.load`, `Marshal.load`, `unserialize`, `ObjectInputStream.readObject` |
| `template_injection` | 문자열로 만든 템플릿. `render_template_string`, `ERB.new`, `Handlebars.compile` |
| `template_render` | 일반적인 템플릿/뷰 렌더링 |
| `xss` | 자동 이스케이프를 우회하는 HTML 출력. `innerHTML`, `dangerouslySetInnerHTML`, `html_safe`, `mark_safe`, `v-html`, 템플릿의 `safe` 필터 |
| `file_io` | 파일 시스템 읽기/쓰기, 파일 전송, 디렉터리 목록 |
| `redirect` | 리다이렉트 응답 |
| `outbound_http` | 외부로 나가는 HTTP 요청(`fetch`, `axios`, `requests`, `http.Get`, `RestTemplate`, `reqwest`). 대상 URI가 리터럴이면 `name`에 함께 들어갑니다 |
| `mass_assignment` | 요청 파라미터를 모델에 그대로 쓰는 경우(`update_attributes`, `Model.create(req.body)`) |
| `crypto_weak` | 약한 암호 요소. MD5나 SHA-1, DES, ECB 모드, RC4, 암호용이 아닌 난수 |
| `webview_load` | 모바일 전용. WebView가 URL이나 HTML을 로드 |
| `intent_redirect` | 모바일 전용. 들어온 딥링크 데이터로 인텐트를 실행 |

callee 이름이 매칭되면 sink의 `source`는 `callee`, 핸들러 텍스트가 매칭되면 `route_source`입니다. 핸들러 텍스트에서는 kind당 sink가 하나까지만 나옵니다.

### validators

| Kind | 의미 |
|---|---|
| `validation` | 입력에 대한 validate, verify, permit 단계. 호출자를 확인하는 validate/verify(`validateSession`, `verifyAuth`)는 가드로 분류합니다 |
| `schema_validation` | 선언하지 않은 필드를 거부하는 스키마 검증. Pydantic, Zod, Joi, Yup, marshmallow, JSON Schema |
| `type_coercion` | 입력을 숫자나 타입이 정해진 파라미터로 강제(`parseInt`, `Integer()`, 타입이 있는 `@PathVariable`) |
| `allowlist_check` | 값을 고정된 집합과 비교 |
| `sanitization` | sanitize, escape, encode, normalize 단계 |
| `query_parameter_binding` | 쿼리 파라미터를 문자열로 이어 붙이지 않고 클라이언트 API로 바인딩 |
| `existence_validation` | 쓰기 전에 존재 여부를 확인(`existsBy...`, 또는 없으면 예외를 던지는 조회) |
| `uniqueness_validation` | 중복/유일성 검사 |
| `expiry_validation` | 토큰이나 세션의 만료 시각 비교 |
| `credential_hashing`, `credential_verification` | Spring Security 패스워드 인코더의 `encode`, `matches` |
| `cookie_httponly`, `cookie_secure` | `HttpOnly`, `Secure`로 설정한 쿠키 |

### signals

모든 엔드포인트에 두 시그널이 붙습니다. `<METHOD> <url>` 이름의 `route_definition`과, 라우트를 보고한 기술 이름의 `technology`입니다. 나머지는 다섯 묶음으로 나뉩니다.

라우트 형태:

| Kind | 의미 |
|---|---|
| `state_change` | 메서드가 `POST`, `PUT`, `PATCH`, `DELETE`이거나, 권한이 걸린 WebSocket 메시지 핸들러인 경우. 순수 gRPC/Thrift 메서드, GraphQL 쿼리, SOAP 읽기 오퍼레이션, 본문 파라미터 없이 읽기 callee만 호출하는 `POST`에는 붙지 않습니다 |
| `path_param` | 경로 파라미터마다 하나 |
| `internal_endpoint` | 아웃바운드 클라이언트 선언. 애플리케이션이 제공하는 엔드포인트가 아니라 호출하는 엔드포인트입니다 |
| `deep_link_input` | 모바일 딥링크나 외부에 공개된 `ContentProvider`가 앱 밖에서 데이터를 받음 |
| `graphql_resolver` | 이 오퍼레이션을 구현하는 Spring GraphQL 리졸버 |

파라미터 이름. `source`는 `param`이고 이름은 `<type>.<name>`입니다.

| Kind | 대표적인 파라미터 이름 |
|---|---|
| `credential_input` | `password`, `token`, `secret`, `api_key`, `authorization`, `jwt`, `bearer`. 핸들러가 `req.body.password`를 읽는데 분석기가 그 파라미터를 뽑지 못했을 때는 `route_source`에서도 나옵니다. 엔드포인트에 프레임워크 가드가 보고된 경우 헤더와 쿠키는 제외합니다. 그 값은 가드가 읽는 자격 증명이기 때문입니다 |
| `identifier_input` | `id`, `_id`나 `Id`로 끝나는 이름, `user`, `account`, `order`, `project` |
| `redirect_input` | `url`, `uri`, `redirect`, `return`, `next`, `continue`, `dest`, `callback` |
| `file_input` | `file`, `upload`, `attachment`, `image`, `filename`, `path` |
| `query_builder_input` | `sort`, `order`, `filter`, `where`, `search`, `select`, `field`, `column` |
| `pii_input` | `email`, `phone`, `ssn`, `dob`, `passport`, `national_id` |
| `html_content_input` | `description`, `html`, `message`, `comment`, `note`, `markdown` |
| `code_input` | `script`, `formula`, `expression`, `command`, `template` |

태그. 엔드포인트 태그는 전부 시그널이 되며, `kind`는 태그 이름이고 `source`는 태거입니다. `admin`, `payment`, `webhook`, `file_upload`를 비롯한 [태거](@/usage/more_features/tagger/index.ko.md)의 태그, `cors`, `csrf-protection`, `rate-limit`, `security-headers` 같은 프레임워크 보호 장치 태그, `graphql-return`이나 `nginx-host` 같은 분석기 메모가 모두 여기로 옵니다. 파라미터 태그(`sqli`, `ssrf`, `idor`)도 같은 방식이고 `source`는 `param_tagger:<tagger>`입니다. 인증 태그만 예외로, 가드가 됩니다.

약해진 보호 장치와 노출. 핸들러 소스에서 매칭합니다.

| Kind | 의미 |
|---|---|
| `csrf_exempt` | 이 라우트의 CSRF 보호가 꺼져 있음(`@csrf_exempt`, `csrf().disable()`, `protect_from_forgery with: :null_session`). 상태 변경 메서드에만 붙습니다 |
| `jwt_unsafe` | JWT 검증이 꺼졌거나 약해짐. `verify=False`, 알고리즘 `none`, `ignoreExpiration: true` |
| `cors_open` | 와일드카드 origin과 `credentials: true`가 함께 있음 |
| `sensitive_response` | 응답에 자격 증명으로 보이는 키(`token`, `password`, `secret`)가 들어 있음 |
| `server_secret_source` | 핸들러가 Spring `@Value` 시크릿을 반환함. `sources`에도 들어갑니다 |
| `log_injection` | 핸들러가 요청 입력이나 자격 증명을 로그에 남김 |
| `foreign_identifier_write` | 요청 본문의 id가 다른 `...Id` 필드에 대입되어 저장되는데 조회나 존재 확인이 없음 |

파생 시그널. 위 항목들을 조합해 만들며 `source`는 `heuristic`입니다.

| Kind | 나오는 조건 |
|---|---|
| `guard_absence` | 상태 변경 엔드포인트에 가드가 하나도 없고 경로에 식별자도 없음. 로그인, 로그아웃, 비밀번호 재설정 라우트는 건너뜁니다 |
| `idor_review` | 위와 같지만 경로에 식별자가 있음 |
| `authz_absence` | 상태 변경 엔드포인트에 `auth_guard`는 있고 `authz_guard`는 없으며 경로에 식별자가 있음 |
| `rate_limit_absence` | 상태 변경 엔드포인트가 본문, 쿼리, 경로로 자격 증명을 받는데 `rate_limit_guard`가 없음 |
| `ssrf` | `outbound_http` sink와 `redirect_input`이 함께 있음 |
| `open_redirect` | `redirect` sink와 `redirect_input`이 함께 있음 |
| `path_traversal` | `file_io` sink와 `file_input`이 함께 있음 |
| `object_lookup` | 식별자 입력과 조회 callee(`findById`, `getOne`, `repo.get`)가 함께 있음 |
| `object_write` | 경로에 식별자가 있는 상태 변경 엔드포인트가 조회 callee 없이 변경 callee(`create`, `update`, `delete`, `save`)를 호출. 감사 로그 기록과 메모리 안에서 값을 만드는 호출(`createFormBuilder`, `CreateAPIError`)은 변경으로 보지 않습니다 |
| `unsafe_method` | `GET`, `HEAD`, `OPTIONS`, `QUERY` 엔드포인트가 변경 callee를 호출. 핸들러가 요청 메서드나 폼 제출 확인(`$form->isSubmitted()`, `form.validate_on_submit()`)으로 분기하면 건너뜁니다 |
| `priority_review` | 종합 점수. 아래에서 설명합니다 |

부재(absence) 시그널 넷은 신뢰도가 일부러 낮습니다(28에서 44). 게이트웨이나 Noir가 읽지 않은 부모 클래스에 있는 가드는 놓칠 수 있으므로, 이 시그널은 "이 라우트를 보호하는 것이 없다"가 아니라 "여기서 감지된 것이 없다"는 뜻입니다.

`priority_review`는 세 가지를 더합니다. 첫째는 엔드포인트의 리뷰 시그널 수(부재 시그널, `csrf_exempt`, `jwt_unsafe`, `cors_open`, `open_redirect`, `ssrf`, `path_traversal`, `sensitive_response`, `server_secret_source`, `unsafe_method`, `log_injection`, `deep_link_input`)입니다. 둘째는 무거운 sink의 kind 수(`sql`, `data_store_query`, `command_exec`, `code_eval`, `deserialization`, `template_injection`, `xss`, `mass_assignment`, `crypto_weak`, `webview_load`, `intent_redirect`)이고, 셋째는 `csrf_exempt`, `jwt_unsafe`, `cors_open`, `open_redirect` 중 하나라도 있으면 붙는 1점입니다. `query_parameter_binding` validator가 있으면 `sql`과 `data_store_query` sink는 세지 않고, `sanitization`이나 `schema_validation`이 있으면 `xss`는 세지 않습니다. 합이 2 미만이면 아무것도 나오지 않습니다. 합이 3 이상이거나, 위 네 시그널 중 하나가 있거나, 무거운 sink kind가 둘 이상이면 `name`이 `high`(신뢰도 90)이고, 나머지는 `medium`(신뢰도 70)입니다. `kind == "priority_review"`와 `confidence >= 80`으로 거르면 우선순위가 높은 라우트만 남습니다.

버킷이 가득 차면 새 항목은 순위가 가장 낮은 항목보다 높을 때만 그 자리를 대신합니다. 파생 시그널과 부재 시그널은 파라미터 단위 항목보다 순위가 높으므로, 파라미터가 많은 라우트에서도 종합 시그널은 남습니다.

## 대표 사용 사례

- **AI SAST**: 엔드포인트 인벤토리와 AI 컨텍스트를 LLM에 함께 넘기면, 라우트 구조를 다시 발견하지 않아도 공격 표면에서 도달 가능한 취약점에 집중할 수 있습니다.
- **수동 트리아지**: 큰 JSON/SARIF 리포트를 sink 종류나 `signals`(예: `guard_absence`)로 정렬하고 거를 수 있습니다.
- **CI 게이팅**: `sinks`는 있고 `validators`는 없는 엔드포인트를 골라 PR에서 위험 엔드포인트로 표시합니다.

## 다른 플래그와 조합

```bash
# 1-hop callee와 AI 컨텍스트 블록을 함께 출력
noir scan . --include callee --ai-context

# LLM 기반 SAST 파이프라인용 JSON 출력
noir scan . --ai-context -f json -o noir-context.json

# 오퍼레이션마다 `x-noir-ai-context`가 붙은 OpenAPI 내보내기
noir scan . --ai-context -f oas3 -o spec.json
```

## 완성도 참고 사항

- AI 컨텍스트는 데이터를 덧붙이기만 합니다. 휴리스틱에 걸리지 않는 엔드포인트는 플래그 없이 돌렸을 때와 똑같이 나옵니다(직렬화된 모델에 `ai_context` 키가 추가되지 않음).
- 휴리스틱은 보수적으로 튜닝되어 있지만 거짓 양성/음성 모두 존재합니다. 항목은 확정된 결론이 아니라 검토를 시작할 단서로 다루세요.
- guard/sink/validator 패턴은 계속 개선됩니다. 패턴을 일부러 언어에 묶지 않았기 때문에, 컨텍스트 스키마 하나가 Noir가 지원하는 모든 프레임워크에 그대로 적용됩니다.
- AI 컨텍스트의 많은 부분이 callee 커버리지에서 비롯됩니다. 현재 어떤 프레임워크가 핸들러 callee를 내보내는지는 [Callee 커버리지](@/usage/supported/callee_coverage/index.ko.md)를 참고하세요.
