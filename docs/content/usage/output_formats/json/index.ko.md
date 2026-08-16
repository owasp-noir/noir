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
noir scan . -f json --no-log
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
  ],
  "errors": []
}
```

## 분석기 실패 기록

분석기 하나가 예외로 죽어도 스캔은 나머지 기술을 계속 처리합니다. `errors`에는 그렇게 건너뛴 분석기가 남기 때문에, 결과가 비어 있는 이유가 "해당 프레임워크가 없어서"인지 "아예 분석하지 못해서"인지 구분할 수 있습니다.

```json
{
  "endpoints": [],
  "passive_results": [],
  "errors": [
    { "tech": "go_gin", "message": "Index out of bounds" }
  ]
}
```

이 키는 항상 출력됩니다. `"errors": []`는 선택된 분석기가 모두 끝까지 실행됐다는 뜻입니다.

`-f yaml`도 같은 키를 담고, `-f sarif`는 `runs[0].invocations[0].executionSuccessful`로 같은 사실을 알립니다. `--strict`를 붙이면 리포트를 출력한 뒤 종료 코드 2로 끝나므로 CI에서 바로 걸러낼 수 있습니다.

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
{"url":"/","method":"GET","params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":3}]},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":8}]},"protocol":"http","tags":[]}
```
