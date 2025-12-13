+++
title = "추가 출력 형식"
description = "Noir는 코드베이스에서 특정 정보를 추출하는 데 도움이 되는 다양한 추가 출력 형식을 제공합니다. 이 페이지는 'only-url', 'only-param', 'markdown-table'과 같은 형식을 사용하여 필요에 맞게 출력을 사용자 정의하는 방법을 설명합니다."
weight = 6
sort_by = "weight"

[extra]
+++

Noir는 특정 정보를 분리해야 할 때를 위한 다양한 특수화된 출력 형식을 지원합니다. 이러한 형식은 추가적인 노이즈 없이 필요한 데이터에 빠르게 액세스할 수 있도록 설계되었습니다. 다음은 사용할 수 있는 가장 유용한 추가 형식 중 일부입니다.

## 특정 정보 필터링

`only-*` 형식을 사용하여 스캔에서 한 가지 유형의 데이터만 추출할 수 있습니다.

### URL만

모든 발견된 URL 목록을 얻으려면 `only-url` 형식을 사용하세요:

```bash
noir -b . -f only-url
```

이렇게 하면 간단한 엔드포인트 목록이 출력됩니다:

```
/
/query
/token
/socket
/1.html
/2.html
```

### 매개변수만

모든 고유 매개변수 이름을 추출하려면 `only-param`을 사용하세요:

```bash
noir -b . -f only-param
```

이렇게 하면 코드베이스에서 찾은 모든 매개변수 이름이 나열됩니다:

```
query
client_id
redirect_url
grant_type
```

### 헤더만

모든 HTTP 헤더 목록을 얻으려면 `only-header`를 사용하세요:

```bash
noir -b . -f only-header
```

이렇게 하면 헤더의 이름이 출력됩니다:

```
x-api-key
Cookie
```

### 쿠키만

모든 쿠키 이름을 나열하려면 `only-cookie`를 사용하세요:

```bash
noir -b . -f only-cookie
```

이렇게 하면 쿠키의 이름만 표시됩니다:

```
my_auth
```

### 태그만

엔드포인트에 태그를 적용했다면 `only-tag`로 나열할 수 있습니다:

```bash
noir -b . -f only-tag -T
```

이렇게 하면 모든 고유 태그가 출력됩니다:

```
sqli
oauth
websocket
```

## 마크다운 테이블 형식

모든 엔드포인트와 해당 매개변수의 깔끔하고 사람이 읽기 쉬운 테이블을 원한다면 `markdown-table` 형식을 사용하세요:

```bash
noir -b . -f markdown-table
```

이렇게 하면 문서나 보고서에 쉽게 복사할 수 있는 마크다운 테이블이 생성됩니다:

| Endpoint    | Protocol | Params                                                              |
|-------------|----------|---------------------------------------------------------------------|
| GET /       | http     | `x-api-key (header)`                                                |
| POST /query | http     | `my_auth (cookie)` `query (form)`                                   |
| GET /token  | http     | `client_id (form)` `redirect_url (form)` `grant_type (form)`        |
| GET /socket | ws       |                                                                     |
| GET /1.html | http     |                                                                     |
| GET /2.html | http     |                                                                     |

## JSON Lines (JSONL) 형식

대용량 데이터셋을 스트리밍하거나 라인별로 처리하려면 `jsonl` 형식을 사용하세요:

```bash
noir -b . -f jsonl
```

이렇게 하면 각 줄이 단일 엔드포인트를 나타내는 JSON 객체가 한 줄에 하나씩 출력됩니다:

```jsonl
{"url":"/","method":"GET","params":[{"name":"x-api-key","type":"header","value":""}]}
{"url":"/query","method":"POST","params":[{"name":"my_auth","type":"cookie","value":""},{"name":"query","type":"form","value":""}]}
{"url":"/token","method":"GET","params":[{"name":"client_id","type":"form","value":""}]}
```

이 형식은 다음과 같은 경우에 특히 유용합니다:
- 대용량 결과 세트의 스트리밍 처리
- 로그 처리 도구와의 통합
- 전체 결과 세트를 메모리에 로드하지 않고 라인별 분석

## Postman 컬렉션 형식

Postman에 직접 가져올 수 있는 Postman 컬렉션을 생성하려면 `postman` 형식을 사용하세요:

```bash
noir -b . -f postman -u https://api.example.com
```

이렇게 하면 발견된 모든 엔드포인트를 메서드, 헤더 및 매개변수와 함께 포함하는 Postman Collection v2.1 형식의 JSON 파일이 생성됩니다. 이 출력을 파일로 저장하고 Postman에 가져와서 대화형 API 테스트를 수행할 수 있습니다.

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

## HTML 보고서 형식

스캔 결과의 시각적 HTML 보고서를 생성하려면 `html` 형식을 사용하세요:

```bash
noir -b . -f html -o report.html
```

이렇게 하면 웹 브라우저에서 열 수 있는 대화형 HTML 문서가 생성됩니다. 보고서에는 다음이 포함됩니다:
- 발견된 엔드포인트 요약
- 상세한 매개변수 정보
- 쉽게 읽을 수 있는 시각적 서식
- 필터링 및 검색을 위한 대화형 요소

이 형식은 다음과 같은 경우에 이상적입니다:
- 비기술적 이해관계자와 결과 공유
- 감사 보고서 작성
- 문서화 목적
- API 표면의 시각적 검사

이러한 특수화된 형식을 사용하면 필요한 정확한 정보를 추출하여 추가 처리, 문서화 또는 다른 도구와의 통합을 위해 사용할 수 있습니다.