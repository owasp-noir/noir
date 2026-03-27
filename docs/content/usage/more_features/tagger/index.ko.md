+++
title = "상황별 분석을 위한 Tagger 사용하기"
description = "엔드포인트와 매개변수에 자동으로 태그를 추가하여 잠재적 보안 위험을 식별합니다."
weight = 3
sort_by = "weight"

+++

엔드포인트와 파라미터에 설명적 태그를 자동으로 추가하여 기능과 잠재적 보안 위험(SQL 인젝션, 인증 엔드포인트 등)을 식별합니다.

![](./tagger.png)

## 사용법

Tagger는 기본적으로 비활성화되어 있습니다.

**모든 태거 활성화**

```bash
noir -b <BASE_PATH> -T
```

**특정 태거만 활성화** (`noir --list-taggers`로 목록 확인)

```bash
noir -b <BASE_PATH> --use-taggers hunt,oauth
```

## 출력

태그는 엔드포인트 레벨과 파라미터 레벨 양쪽의 `tags` 배열에 추가됩니다. 각 태그에는 `name`(짧은 식별자, 예: `sqli`, `oauth`), 사람이 읽을 수 있는 `description`, 그리고 태그를 생성한 `tagger`(예: `Hunt`는 취약점 패턴, `Oauth`는 인증 흐름)가 들어갑니다.

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
          "description": "This parameter may be vulnerable to SQL Injection attacks.",
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
      "description": "Suspected OAuth endpoint for granting 3rd party access.",
      "tagger": "Oauth"
    }
  ]
}
```
