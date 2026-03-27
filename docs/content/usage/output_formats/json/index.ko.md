+++
title = "JSON 및 JSONL"
description = "JSON 또는 JSONL 형식으로 Noir 스캔 결과를 생성합니다."
weight = 2
sort_by = "weight"

+++

Noir는 두 가지 JSON 계열 출력을 지원합니다.

*   **JSON**: 전체 결과를 하나의 JSON 객체로 출력
*   **JSONL**: 줄마다 하나의 JSON 객체를 출력하여 스트리밍이나 대용량 처리에 적합

## JSON 출력

`-f json`으로 JSON을 출력합니다. `--no-log`를 함께 쓰면 로그 메시지 없이 JSON만 출력되므로, 다른 도구로 파이핑할 때 깔끔합니다.

```bash
noir -b . -f json --no-log
```

결과는 `endpoints` 배열을 포함하는 객체입니다. 각 엔드포인트에는 URL, HTTP 메서드, 파라미터(타입: `cookie`, `form`, `header`, `json` 등), 소스 코드 위치(`details.code_paths`), 그리고 Tagger가 붙인 보안 태그가 들어갑니다.

```json
{
  "endpoints": [
    {
      "url": "/",
      "method": "GET",
      "params": [
        {
          "name": "x-api-key",
          "value": "",
          "param_type": "header",
          "tags": []
        }
      ],
      "details": {
        "code_paths": [
          {
            "path": "./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
            "line": 3
          }
        ]
      },
      "protocol": "http",
      "tags": []
    }
  ]
}
```

## JSONL 출력

[JSON Lines](https://jsonlines.org/) 형식은 줄마다 독립된 JSON 객체를 출력합니다. `jq`로 파이핑하거나, 대량의 결과를 메모리에 다 올리지 않고 한 줄씩 처리할 때 유용합니다.

```bash
noir -b . -f jsonl --no-log
```

아래와 같이 각 줄은 하나의 엔드포인트입니다.

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":3}]},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":8}]},"protocol":"http","tags":[]}
```
