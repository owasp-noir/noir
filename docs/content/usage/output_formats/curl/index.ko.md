+++
title = "HTTP 클라이언트 명령어"
description = "Noir 스캔 결과에서 cURL, HTTPie, PowerShell 명령어를 생성합니다."
weight = 1
sort_by = "weight"

+++

발견된 엔드포인트를 바로 실행할 수 있는 HTTP 클라이언트 명령어로 변환합니다. `-u`로 base URL을 지정하면 경로 앞에 자동으로 붙여줍니다.

## cURL

[cURL](https://curl.se/)은 가장 널리 쓰이는 커맨드라인 HTTP 클라이언트입니다. 생성되는 명령어에는 `-i`(응답 헤더 포함), `-X`(HTTP 메서드), `-d`(요청 바디), `-H`(헤더), `--cookie`(쿠키) 등의 플래그가 적절히 들어갑니다.

```bash
noir -b . -f curl -u https://www.example.com
```

출력 예시
```bash
curl -i -X GET https://www.example.com/ -H "x-api-key: "
curl -i -X POST https://www.example.com/query -d "query=" --cookie "my_auth="
curl -i -X GET https://www.example.com/token -d "client_id=&redirect_url=&grant_type="
```

## HTTPie

[HTTPie](https://httpie.io/)는 cURL보다 직관적인 문법에 컬러 출력과 JSON 지원이 기본 내장된 HTTP 클라이언트입니다.

```bash
noir -b . -f httpie -u https://www.example.com
```

출력 예시
```bash
http GET https://www.example.com/ "x-api-key: "
http POST https://www.example.com/query "query=" "Cookie: my_auth="
http GET https://www.example.com/token "client_id=&redirect_url=&grant_type="
```

## PowerShell

Windows 환경이라면 별도 도구 설치 없이 바로 쓸 수 있는 [Invoke-WebRequest](https://learn.microsoft.com/ko-kr/powershell/module/microsoft.powershell.utility/invoke-webrequest) 명령어를 생성합니다.

```bash
noir -b . -f powershell -u https://www.example.com
```

출력 예시
```powershell
Invoke-WebRequest -Method GET -Uri "https://www.example.com/" -Headers @{"x-api-key"=""}
Invoke-WebRequest -Method POST -Uri "https://www.example.com/query" -Headers @{"Cookie"="my_auth="} -Body "query=" -ContentType "application/x-www-form-urlencoded"
Invoke-WebRequest -Method GET -Uri "https://www.example.com/token" -Body "client_id=&redirect_url=&grant_type=" -ContentType "application/x-www-form-urlencoded"
```

## 파라미터 값 채우기

Noir는 기본적으로 파라미터 값을 비워두기 때문에(`x-api-key=`, `query=` …) 생성된 명령은 템플릿처럼 동작합니다. 그대로 실행하거나 퍼징 입력 시드를 만들고 싶다면 `--set-pvalue` 계열로 값을 미리 채울 수 있습니다.

| 플래그 | 적용 범위 |
|---|---|
| `--set-pvalue VALUE` | 모든 파라미터 타입 |
| `--set-pvalue-query VALUE` | 쿼리 스트링 |
| `--set-pvalue-form VALUE` | 폼 바디 (`application/x-www-form-urlencoded`) |
| `--set-pvalue-json VALUE` | JSON 바디 |
| `--set-pvalue-header VALUE` | 요청 헤더 |
| `--set-pvalue-cookie VALUE` | 쿠키 |
| `--set-pvalue-path VALUE` | 경로 파라미터 |

`VALUE`는 두 가지 형태를 받습니다.

| 형태 | 동작 |
|---|---|
| `<value>` | 대상 타입의 모든 파라미터에 사용 |
| `<name>=<value>` 또는 `<name>:<value>` | 이름이 `<name>`인 파라미터에만 사용 |

모든 플래그는 반복 사용 가능하며, 동일 파라미터에 매치되면 타입별 규칙이 일반 `--set-pvalue`보다 우선합니다.

```bash
# 모든 파라미터를 `test`로 채움
noir -b . -f curl -u https://example.com --set-pvalue "test"

# `Authorization` 헤더와 `id` 경로 파라미터에만 값 채움
noir -b . -f curl -u https://example.com \
  --set-pvalue-header "Authorization=Bearer xyz" \
  --set-pvalue-path "id=42"

# 쿼리/폼은 기본 `1`이지만 `limit`은 항상 10
noir -b . -f curl -u https://example.com \
  --set-pvalue-query "1" \
  --set-pvalue-query "limit=10"
```

같은 플래그는 HTTPie와 PowerShell 출력에도 적용되며, OpenAPI / Postman / JSON 등 값이 렌더링되는 다른 형식에도 전파됩니다.
