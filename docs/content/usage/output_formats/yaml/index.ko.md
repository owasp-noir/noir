+++
title = "YAML"
description = "이 페이지는 YAML 형식으로 스캔 결과를 생성하는 방법을 설명합니다. YAML은 다른 도구와의 통합이나 수동 검토를 위해 사람이 읽기 쉽고 파싱하기 쉬운 옵션입니다."
weight = 3
sort_by = "weight"

+++

YAML (YAML Ain't Markup Language)은 사람이 읽기 쉬운 구문으로 알려진 인기 있는 데이터 직렬화 형식입니다. Noir는 수동 검사부터 다른 도구와의 자동화된 처리까지 다양한 목적에 유용한 YAML로 결과를 출력할 수 있습니다.

## YAML 출력 생성 방법

YAML 형식으로 스캔 결과를 얻으려면 Noir를 실행할 때 `-f yaml` 또는 `--format yaml` 플래그를 사용하세요. 추가 로깅 정보를 억제하고 출력을 깔끔하게 유지하기 위해 `--no-log` 플래그를 사용하는 것도 좋은 방법입니다.

```bash
noir -b . -f yaml --no-log
```

이 명령은 발견된 엔드포인트에 대한 모든 정보를 포함하는 잘 구조화된 YAML 문서를 생성합니다.

## YAML 출력 예제

YAML 출력이 어떻게 보이는지에 대한 샘플입니다:

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
# ... 다른 모든 엔드포인트에 대해서도 계속
```

보시다시피 YAML 출력은 URL, HTTP 메서드, 매개변수 및 소스 코드에서 발견된 정확한 위치를 포함하여 각 엔드포인트의 명확하고 상세한 분석을 제공합니다. 이를 통해 Noir의 결과를 기존 CI/CD 파이프라인, 보고 도구 또는 개발 워크플로의 다른 부분에 쉽게 통합할 수 있습니다.