+++
title = "JSON 및 JSONL"
description = "JSON 또는 JSONL 형식으로 Noir 스캔 결과를 생성합니다."
weight = 2
sort_by = "weight"

+++

Noir의 JSON 출력은 두 가지입니다.

*   JSON: 전체 결과를 JSON 객체 하나로 출력
*   JSONL: 줄마다 JSON 객체 하나를 출력. 스트리밍이나 큰 결과 처리에 적합

{% mascot(mood="dev") %}
JSON은 다음 단계가 다 읽는 형식이야. jq든 스크립트든 AI 감사 컨텍스트든 그대로 넘겨.
{% end %}

## JSON 출력

`-f json`으로 JSON을 출력합니다. 로그는 stderr로 나가므로 stdout에는 JSON만 담기고, 그대로 다른 도구로 파이프해도 됩니다. 로그까지 숨기려면 `--no-log`를 함께 쓰세요.

```bash
noir scan . -f json --no-log
```

결과는 `endpoints`, `passive_results`, `errors` 배열을 담은 객체입니다. 각 엔드포인트에는 URL, HTTP 메서드, 파라미터(타입: `query`, `path`, `header`, `cookie`, `form`, `json`, `file`, `xml` 등), 소스 코드 위치(`details.code_paths`), 엔드포인트를 만든 분석기(`details.technology`), 그리고 태거가 붙인 보안 태그가 들어갑니다.

같은 엔드포인트를 여러 분석기가 찾으면(예: Go 라우터와 프로젝트의 OpenAPI 문서) Noir는 하나의 항목으로 합칩니다. `details.technology`는 병합에서 이긴 분석기이고, `details.technologies`는 기여한 모든 분석기를 정렬·중복 제거해 담은 목록입니다. 이 목록은 항목이 둘 이상일 때만 출력되므로, 분석기 하나만 찾은 엔드포인트에는 `technology`만 있습니다. 출처가 모두 필요하면 `technologies`를 읽고, 이 키가 없을 때는 `[technology]`로 대체하면 됩니다.

```json
"details": {
  "code_paths": [
    { "path": "routers/router.go", "line": 42 },
    { "path": "swagger/swagger.json", "line": 1300 }
  ],
  "technology": "go_beego",
  "technologies": ["go_beego", "oas2"]
}
```

모노레포에서는 같은 라우트를 두 앱이 제공할 수 있고, Noir는 이를 두 개의 엔드포인트로 유지합니다. `details.project`는 각 엔드포인트가 속한 앱을 나타냅니다. 첫 번째 소스 파일에서 위쪽으로 찾은 가장 가까운 빌드 매니페스트(`pyproject.toml`, `package.json`, `go.mod`, `pom.xml` 등)의 디렉터리를 스캔 기준 경로에 대한 상대 경로로 적습니다. 이름 붙일 것이 없으면 출력되지 않습니다. 단일 프로젝트 스캔(매니페스트가 기준 경로에 있음)이나 코드가 아닌 명세에서 온 엔드포인트가 그렇습니다. 따라서 기존 리포트는 바뀌지 않습니다. `noir query --project services/orders`로 필터링할 수 있습니다.

```json
"details": {
  "code_paths": [{ "path": "mono/services/orders/app.py", "line": 7 }],
  "technology": "python_flask",
  "project": "services/orders"
}
```

Noir가 보고하는 내용 중에는 정의를 따라가서 읽은 것도 있고, 추정한 것도 있습니다. `resolution`은 엔드포인트의 주장 가운데 끝까지 읽지 못한 것을 나열하며, 각 주장에는 두 값 중 하나가 붙습니다.

*   `heuristic`: 이름, 모양, 위치로 맞춘 것
*   `unresolved`: 참조는 보았지만 따라가지 못한 것

끝까지 읽은 주장은 나열하지 않고, 나열할 것이 없는 엔드포인트에는 `resolution` 키가 없습니다. 이번 버전은 Go 분석기만 주장 두 개를 표시합니다. 따라서 키가 없다고 해서 그 엔드포인트의 모든 주장이 검증된 것은 아닙니다. 표시된 것이 없다는 뜻일 뿐입니다.

Go 분석기는 `prefix`와 `handler`를 표시합니다. `prefix: unresolved`는 라우트 경로 앞쪽에 Noir가 읽지 못한 피연산자가 있고, URL은 그 뒤의 리터럴 부분이라는 뜻입니다. oapi-codegen은 모든 오퍼레이션을 `r.Get(options.BaseURL+"/status", ...)`로 등록하며, 이것은 `/status`로 보고됩니다. 실제 경로 앞에는 무언가가 더 있을 수 있습니다. Noir가 읽은 그룹이나 마운트 접두사는 그대로 붙지만(`r.Mount("/api", ...)`이면 `/api/status`), 그 사이의 피연산자는 여전히 읽지 못했으므로 표시는 남습니다. 접두사를 끝까지 읽지 못한 그룹에 등록된 라우트에도, 그 아래 중첩된 그룹의 라우트에도, 라우트가 어느 파일이나 패키지에 있든 같은 표시가 붙습니다. apache/answer의 `r.Group(uiConf.APIBaseURL + "/answer/api/v1")`은 뒤쪽 `/answer/api/v1`을 남기고, woodpecker의 `e.Group(server.Config.Server.RootPath)`는 라우트 경로에 아무것도 더하지 않습니다. 그룹 매개변수(`func register(g *echo.Group)`, `*gin.RouterGroup`)를 받는 라우터 빌더 함수도, 읽을 수 있는 그룹을 넘기는 호출 지점을 찾지 못하면 같은 표시가 붙습니다. 루트 라우터일 수도 있는 인터페이스 매개변수(`fiber.Router`, `gin.IRouter`)는 표시하지 않습니다. 접두사를 끝까지 읽은 그룹의 라우트에는 표시가 붙지 않습니다. 메서드와 경로가 같은 두 행이 병합되면, 어느 한쪽이라도 표시한 주장은 표시된 채로 남습니다. 이런 행은 `noir query --resolution unresolved`로 볼 수 있습니다.

```json
{
  "url": "/api/status",
  "method": "GET",
  "resolution": { "prefix": "unresolved" },
  "details": {
    "code_paths": [{ "path": "api/api.gen.go", "line": 32 }],
    "technology": "go_chi"
  }
}
```

`handler: heuristic`은 참조와 정의의 연결을 확인하지 못한 채 이름, wrapper의 모양, 위치로 핸들러 정의를 골랐다는 뜻입니다. 핸들러의 이름, 경로, 줄 번호는 고른 정의를 그대로 가리키며, 이런 행은 `noir query --resolution heuristic`으로 볼 수 있습니다. 참조는 있지만 정의를 찾지 못한 핸들러는 표시하지 않습니다.

YAML, JSONL, TOML 출력에도 같은 필드가 들어가고, 일반 리포트에는 `resolution` 행으로 출력됩니다.

전체 리포트는 다음과 같습니다. 태거를 켠 상태(`-T`)로 만든 것이어서 `tags` 배열이 채워져 있습니다.

```json
{
  "endpoints": [
    {
      "callees": [],
      "url": "/query",
      "method": "POST",
      "internal": false,
      "details": {
        "code_paths": [
          {
            "path": "spec/functional_test/fixtures/crystal/kemal/src/testapp.cr",
            "line": 17
          }
        ],
        "technology": "crystal_kemal"
      },
      "protocol": "http",
      "kind": "",
      "tags": [],
      "params": [
        {
          "name": "my_auth",
          "value": "",
          "param_type": "cookie",
          "tags": []
        },
        {
          "name": "query",
          "value": "",
          "param_type": "form",
          "tags": []
        }
      ]
    },
    {
      "callees": [],
      "url": "/token",
      "method": "GET",
      "internal": false,
      "details": {
        "code_paths": [
          {
            "path": "spec/functional_test/fixtures/crystal/kemal/src/testapp.cr",
            "line": 22
          }
        ],
        "technology": "crystal_kemal"
      },
      "protocol": "http",
      "kind": "",
      "tags": [
        {
          "name": "oauth",
          "description": "Suspected OAuth endpoint for granting 3rd party access.",
          "tagger": "Oauth"
        }
      ],
      "params": [
        {
          "name": "client_id",
          "value": "",
          "param_type": "form",
          "tags": []
        },
        {
          "name": "redirect_url",
          "value": "",
          "param_type": "form",
          "tags": [
            {
              "name": "ssrf",
              "description": "This parameter may be vulnerable to Server Side Request Forgery (SSRF) attacks.",
              "tagger": "Hunt"
            }
          ]
        },
        {
          "name": "grant_type",
          "value": "",
          "param_type": "form",
          "tags": []
        }
      ]
    }
  ],
  "passive_results": [],
  "errors": []
}
```

## 분석기 실패 기록

분석기 하나가 예외를 던지면 로그를 남기고 건너뛰며, 스캔은 나머지 분석기로 계속 진행합니다. 읽거나 파싱할 수 없는 파일 하나(예: 파싱 시간 상한을 넘긴 파일) 역시 그 파일만 건너뛰고 스캔은 이어집니다. `errors`에는 두 경우가 모두 남기 때문에, 결과가 비어 있는 이유가 "해당 프레임워크가 없어서"인지 "아예 분석하지 못해서"인지, 그리고 조용히 빠진 파일이 있었는지 구분할 수 있습니다.

```json
{
  "endpoints": [],
  "passive_results": [],
  "errors": [
    { "tech": "go_gin", "message": "Index out of bounds" },
    { "tech": "rust_axum", "message": "skipped 2 files: src/gen.rs, src/vendor.rs; first error: ts_parser_parse_string returned null (timed out after 10000ms, or out of memory)" }
  ]
}
```

건너뛴 파일은 파일마다 한 줄이 아니라 기술별로 묶어서 개수와 예시 경로 최대 5개로 기록합니다. 그래야 깨진 체크아웃 하나가 리포트를 뒤덮지 않습니다.

이 키는 항상 출력됩니다. `"errors": []`는 선택된 분석기가 주어진 모든 파일을 끝까지 처리했다는 뜻입니다.

`-f yaml`도 같은 키를 담고, `-f sarif`는 `runs[0].invocations[0].executionSuccessful`로 같은 사실을 알립니다. `--strict`를 붙이면 분석기 실패나 건너뛴 파일이 있을 때 리포트를 쓴 뒤 종료 코드 2로 끝납니다.

```bash
noir scan . -f json --no-log --strict > endpoints.json
```

## JSONL 출력

[JSON Lines](https://jsonlines.org/) 형식은 줄마다 독립된 JSON 객체를 출력합니다. `jq`로 넘기거나, 큰 결과를 메모리에 다 올리지 않고 한 줄씩 처리할 때 쓰세요.

```bash
noir scan . -f jsonl --no-log
```

각 줄은 독립된 엔드포인트 객체 하나입니다. `-P`를 쓰면 엔드포인트 뒤에 패시브 스캔 결과가 한 줄에 하나씩 붙습니다(엔드포인트에는 `url`, `method`가 있고, 패시브 결과에는 `id`, `info`가 있어서 구분할 수 있습니다). 분석기가 실패하면 실패 하나당 `tech`, `message`가 담긴 줄이 맨 뒤에 붙습니다(JSON의 `errors` 항목과 같은 내용). 문제없는 스캔에는 이 줄이 없습니다. 스캔이 온전하지 않을 때 0이 아닌 종료 코드를 받으려면 `--strict`를 쓰세요.

```jsonl
{"callees":[],"url":"/","method":"GET","internal":false,"details":{"code_paths":[{"path":"./src/testapp.cr","line":3}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}]}
{"callees":[],"url":"/query","method":"POST","internal":false,"details":{"code_paths":[{"path":"./src/testapp.cr","line":17}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}]}
```
