+++
title = "YAML"
description = "사람이 읽기 쉬운 YAML 형식으로 스캔 결과를 생성합니다."
weight = 3
sort_by = "weight"

+++

수동 검사 또는 자동화된 처리를 위해 사람이 읽기 쉬운 YAML 형식으로 스캔 결과를 출력합니다.

## 사용법

YAML 출력 생성:

```bash
noir -b . -f yaml --no-log
```

## 출력 예제

```yaml
endpoints:
  - url: /
    method: GET
    params:
      - name: x-api-key
        value: ""
        param_type: header
        tags: []
    details:
      code_paths:
        - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
          line: 3
    protocol: http
    tags: []
  - url: /query
    method: POST
    params:
      - name: my_auth
        value: ""
        param_type: cookie
        tags: []
      - name: query
        value: ""
        param_type: form
        tags: []
    details:
      code_paths:
        - path: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr
          line: 8
    protocol: http
    tags: []
```