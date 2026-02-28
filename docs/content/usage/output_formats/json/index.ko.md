+++
title = "JSON 및 JSONL"
description = "JSON 또는 JSONL 형식으로 Noir 스캔 결과를 생성합니다."
weight = 2
sort_by = "weight"

+++

Noir는 JSON과 JSONL 출력 형식을 지원합니다:

*   **JSON**: 모든 결과를 포함하는 단일 JSON 객체
*   **JSONL**: 각 줄이 별도의 JSON 객체로, 대용량 데이터 스트리밍에 유용

## JSON 출력

JSON 출력 생성:

```bash
noir -b . -f json --no-log
```

출력 구조:

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

JSONL 출력 생성:

```bash
noir -b . -f jsonl --no-log
```

출력 형식 (줄당 하나의 JSON 객체):

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":3}]},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":8}]},"protocol":"http","tags":[]}
```