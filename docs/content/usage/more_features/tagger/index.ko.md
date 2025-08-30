+++
title = "상황별 분석을 위한 Tagger 사용하기"
description = "Noir의 Tagger 기능을 사용하여 엔드포인트와 매개변수에 상황별 태그를 자동으로 추가하는 방법을 알아보세요. 이를 통해 애플리케이션의 흥미롭거나 잠재적으로 취약한 영역을 빠르게 식별할 수 있습니다."
weight = 3
sort_by = "weight"

[extra]
+++

Tagger는 Noir의 강력한 기능으로 발견한 엔드포인트와 매개변수에 설명적인 태그를 자동으로 추가합니다. 이러한 태그는 애플리케이션의 특정 부분과 관련된 기능이나 잠재적 보안 위험에 대한 귀중한 정보를 제공할 수 있습니다. 이를 통해 가장 중요한 영역에 빠르게 주의를 집중할 수 있습니다.

예를 들어, Tagger는 SQL 인젝션에 취약할 수 있는 매개변수나 인증과 관련된 엔드포인트를 식별할 수 있습니다.

![](./tagger.png)

## Tagger 사용 방법

Tagger는 기본적으로 비활성화되어 있습니다. 몇 가지 방법으로 활성화할 수 있습니다:

*   **모든 태거 활성화**: 사용 가능한 모든 태거를 실행하려면 `-T` 또는 `--use-all-taggers` 플래그를 사용하세요.

    ```bash
    noir -b <BASE_PATH> -T
    ```

*   **특정 태거 활성화**: 특정 태거만 실행하려면 `--use-taggers` 플래그로 지정할 수 있습니다. `noir --list-taggers`를 실행하여 사용 가능한 모든 태거 목록을 찾을 수 있습니다.

    ```bash
    noir -b <BASE_PATH> --use-taggers hunt,oauth
    ```

## 출력 이해하기

Tagger를 사용하면 태그가 출력에 포함됩니다. JSON이나 YAML 형식을 사용하는 경우 태그는 각 엔드포인트와 매개변수의 `tags` 배열에 추가됩니다.

다음은 태그가 포함된 JSON 출력의 예제입니다:

```json
{
  "url": "/query",
  "method": "POST",
  "params": [
    {
      "name": "query",
      "value": "",
      "param_type": "form",
      "tags": [
        {
          "name": "sqli",
          "description": "이 매개변수는 SQL 인젝션 공격에 취약할 수 있습니다.",
          "tagger": "Hunt"
        }
      ]
    }
  ],
  "protocol": "http",
  "tags": []
},
{
  "url": "/token",
  "method": "GET",
  "protocol": "http",
  "tags": [
    {
      "name": "oauth",
      "description": "제3자 액세스 권한 부여를 위한 OAuth 엔드포인트로 의심됩니다.",
      "tagger": "Oauth"
    }
  ]
}
```

Tagger를 사용하면 스캔 결과를 귀중한 정보로 풍부하게 만들어 애플리케이션을 이해하고 보안 노력의 우선순위를 정하기 쉬워집니다.