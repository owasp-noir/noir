+++
title = "추가 출력 형식"
description = "only-url, only-param, markdown-table, Postman 컬렉션 등 특수 출력 형식입니다."
weight = 6
sort_by = "weight"

+++

## `only-*` 형식으로 필터링

스캔 결과에서 단일 유형의 데이터를 추출합니다.

### URL만

```bash
noir scan . -f only-url
```

```
/
/query
/token
/socket
/1.html
/2.html
```

### 매개변수만

```bash
noir scan . -f only-param
```

```
query
client_id
redirect_url
grant_type
```

### 헤더만

```bash
noir scan . -f only-header
```

```
x-api-key
Cookie
```

### 쿠키만

```bash
noir scan . -f only-cookie
```

```
my_auth
```

### 태그만

```bash
noir scan . -f only-tag -T
```

```
sqli
oauth
websocket
```

## 마크다운 테이블

```bash
noir scan . -f markdown-table
```

| Endpoint    | Protocol | Params                                                              |
|-------------|----------|---------------------------------------------------------------------|
| GET /       | http     | `x-api-key (header)`                                                |
| POST /query | http     | `my_auth (cookie)` `query (form)`                                   |
| GET /token  | http     | `client_id (form)` `redirect_url (form)` `grant_type (form)`        |
| GET /socket | ws       |                                                                     |
| GET /1.html | http     |                                                                     |
| GET /2.html | http     |                                                                     |

## TOML

```bash
noir scan . -f toml
```

```toml
[[endpoints]]
url = "/users"
method = "GET"

[[endpoints.params]]
name = "page"
type = "query"
value = ""

[[endpoints]]
url = "/users"
method = "POST"

[[endpoints.params]]
name = "name"
type = "json"
value = ""
```

설정 파일과 같은 형식이라 터미널에서 훑어보기 좋고, 엔드포인트를 다른 선언적 설정과 함께 프로젝트 설정에 붙여넣기에도 적합합니다. TOML 직렬화는 전체 엔드포인트 모델을 그대로 담으며 `--include callee` 와 `--ai-context` 플래그가 켜져 있을 때 그 필드도 포함합니다. `--diff-path` 와 함께 `-f toml` 을 쓰면 diff 결과도 같은 형식으로 출력됩니다.

## JSON Lines (JSONL)

```bash
noir scan . -f jsonl
```

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","type":"header","value":""}]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","type":"cookie","value":""},{"name":"query","type":"form","value":""}]}
{"url":"/token","method":"GET","params":[{"name":"client_id","type":"form","value":""}]}
```

대용량 결과 세트의 스트리밍 처리 및 라인별 분석에 유용합니다.

## Postman 컬렉션

```bash
noir scan . -f postman -u https://api.example.com
```

Postman Collection v2.1 형식의 JSON 파일을 생성합니다. 출력을 저장하고 Postman에 가져와서 대화형 API 테스트를 수행할 수 있습니다.

```json
{
  "info": {
    "name": "Noir Scan Results",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "GET /",
      "request": {
        "method": "GET",
        "header": [
          {
            "key": "x-api-key",
            "value": ""
          }
        ],
        "url": "https://api.example.com/"
      }
    }
  ]
}
```
