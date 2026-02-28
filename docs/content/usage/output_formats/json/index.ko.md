+++
title = "JSON 및 JSONL"
description = "JSON 또는 JSONL 형식으로 Noir 스캔 결과를 얻는 방법을 알아보세요. 이 가이드는 두 형식의 예제를 제공하고 생성 방법을 설명합니다."
weight = 2
sort_by = "weight"

+++

Noir는 JSON과 JSONL을 모두 출력 형식으로 지원하여 스캔 결과를 처리하는 방법에 유연성을 제공합니다.

*   **JSON (JavaScript Object Notation)**은 사람과 기계 모두 이해하기 쉬운 표준적이고 가벼운 형식입니다. 일회성 분석이나 단일 JSON 객체를 기대하는 도구와 통합하기에 좋은 선택입니다.
*   **JSONL (JSON Lines)**은 각 줄이 별도의 유효한 JSON 객체인 형식입니다. 이는 대용량 데이터를 스트리밍하는 데 특히 유용한데, 전체 파일을 메모리에 로드하지 않고도 결과를 한 줄씩 처리할 수 있기 때문입니다.

## JSON 출력

JSON 형식으로 결과를 얻으려면 `-f json` 또는 `--format json` 플래그를 사용하세요. 출력을 깔끔하게 유지하기 위해 `--no-log`를 사용하는 것도 좋은 방법입니다.

```bash
noir -b . -f json --no-log
```

이는 `endpoints` 배열을 포함하는 단일 JSON 객체를 생성합니다:

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

JSONL 형식으로 결과를 얻으려면 `-f jsonl` 플래그를 사용하세요:

```bash
noir -b . -f jsonl --no-log
```

이는 각 엔드포인트가 별도의 줄에 있는 출력을 생성합니다:

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","value":"","param_type":"header","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":3}]},"protocol":"http","tags":[]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","value":"","param_type":"cookie","tags":[]},{"name":"query","value":"","param_type":"form","tags":[]}],"details":{"code_paths":[{"path":"./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr","line":8}]},"protocol":"http","tags":[]}
```

## 사용 사례

### JSON이 적합한 경우:
- 작은 결과 세트
- 단일 JSON 객체를 기대하는 도구와의 통합
- 수동 검사 및 분석

### JSONL이 적합한 경우:
- 대용량 결과 세트
- 스트리밍 처리
- 각 엔드포인트를 개별적으로 처리해야 하는 경우

두 형식 모두 자동화된 워크플로에 쉽게 통합할 수 있으며 다른 보안 도구 및 스크립트에 의해 쉽게 파싱됩니다.