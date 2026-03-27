+++
title = "YAML"
description = "사람이 읽기 쉬운 YAML 형식으로 스캔 결과를 생성합니다."
weight = 3
sort_by = "weight"

+++

스캔 결과를 YAML로 출력합니다. JSON과 같은 정보를 담고 있지만 들여쓰기 기반이라 눈으로 훑어보기 편합니다.

## 사용법

```bash
noir -b . -f yaml --no-log
```

## 출력 예제

구조는 JSON과 동일합니다. `endpoints` 목록 아래에 URL, HTTP 메서드, 파라미터, 소스 경로, 태그 정보가 들어갑니다.

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
