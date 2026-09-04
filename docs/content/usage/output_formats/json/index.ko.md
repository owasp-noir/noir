+++
title = "JSON 및 JSONL"
description = "JSON 또는 JSONL 형식으로 Noir 스캔 결과를 생성합니다."
weight = 2
sort_by = "weight"

+++

Noir는 두 가지 JSON 계열 출력을 지원합니다.

*   **JSON**: 전체 결과를 하나의 JSON 객체로 출력
*   **JSONL**: 줄마다 하나의 JSON 객체를 출력하여 스트리밍이나 대용량 처리에 적합

{% mascot(mood="dev") %}
JSON은 다음 단계가 읽는 포맷이야. jq든 스크립트든 AI 감사 컨텍스트든 그대로 넘겨.
{% end %}

## JSON 출력

`-f json`으로 JSON을 출력합니다. `--no-log`를 함께 쓰면 로그 메시지 없이 JSON만 출력되므로, 다른 도구로 파이핑할 때 깔끔합니다.

```bash
noir scan . -f json --no-log
```

결과는 `endpoints`, `passive_results`, `errors` 배열을 담은 객체입니다. 각 엔드포인트에는 URL, HTTP 메서드, 파라미터(타입: `cookie`, `form`, `header`, `json` 등), 소스 코드 위치(`details.code_paths`), 해당 엔드포인트를 만든 분석기(`details.technology`), 그리고 Tagger가 붙인 보안 태그가 들어갑니다. 아래 예시는 태거를 켠 상태(`-T`)로 만든 것이며, `tags` 배열이 채워진 이유도 그 때문입니다.

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

분석기 하나가 예외로 죽어도 스캔은 나머지 기술을 계속 처리합니다. 읽거나 파싱할 수 없는 파일 하나(예: 파싱 시간 상한을 넘긴 파일) 역시 그 파일만 건너뛰고 스캔은 이어집니다. `errors`에는 두 경우가 모두 남기 때문에, 결과가 비어 있는 이유가 "해당 프레임워크가 없어서"인지 "아예 분석하지 못해서"인지, 그리고 조용히 빠진 파일이 있었는지 구분할 수 있습니다.

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

건너뛴 파일은 파일마다 한 줄이 아니라 기술별로 묶어서 개수와 예시 경로 최대 5개로 기록합니다. 깨진 체크아웃 하나가 리포트를 뒤덮지 않도록 하기 위해서입니다.

이 키는 항상 출력됩니다. `"errors": []`는 선택된 분석기가 주어진 모든 파일을 끝까지 처리했다는 뜻입니다.

`-f yaml`도 같은 키를 담고, `-f sarif`는 `runs[0].invocations[0].executionSuccessful`로 같은 사실을 알립니다. `--strict`를 붙이면 스캔이 degraded 상태(분석기 실패나 건너뛴 파일이 있는 경우)일 때 리포트를 출력한 뒤 종료 코드 2로 끝나므로 CI에서 바로 걸러낼 수 있습니다.

```bash
noir scan . -f json --no-log --strict > endpoints.json
```

## JSONL 출력

[JSON Lines](https://jsonlines.org/) 형식은 줄마다 독립된 JSON 객체를 출력합니다. `jq`로 파이핑하거나, 대량의 결과를 메모리에 다 올리지 않고 한 줄씩 처리할 때 유용합니다.

```bash
noir scan . -f jsonl --no-log
```

아래와 같이 각 줄은 하나의 엔드포인트입니다.

```jsonl
{"callees":[],"url":"/","method":"GET","internal":false,"details":{"code_paths":[{"path":"src/testapp.cr","line":3}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}]}
{"callees":[],"url":"/query","method":"POST","internal":false,"details":{"code_paths":[{"path":"src/testapp.cr","line":17}],"technology":"crystal_kemal"},"protocol":"http","kind":"","tags":[],"params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}]}
```
