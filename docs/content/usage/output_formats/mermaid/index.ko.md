+++
title = "Mermaid 차트"
description = "Noir 스캔 결과에서 API 구조를 시각화하는 Mermaid 마인드맵을 생성합니다."
weight = 5
sort_by = "weight"

+++

API 엔드포인트를 대화형 [Mermaid 마인드맵](https://mermaid-js.github.io/mermaid/#/mindmap)으로 시각화하여 API 구조를 파악합니다.

## 사용법

마인드맵 생성:

```bash
noir -b . -f mermaid
```

## 출력 예제

<details>
    <summary>Mermaid 출력</summary>

```
mindmap
  root((API))
    GET
    about
      GET
      GET
      POST
        body
          data
          id
    gems
      GET
    gems_json
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        cookies
          cookie
        body
          query
          sort
    gems_yml
      GET
        cookies
          cookie
        body
          query
          sort
      PUT
        cookies
          cookie
        body
          query
          sort
    path_111
      PUT
    pets
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        body
          name
      param_petId
        GET
          body
            petId
        PUT
          body
            breed
            name
            petId
    shards
      GET
    users
      POST
        body
          email
          name
      param_userId
        GET
          headers
            Authorization
          body
            userId
    v1
      pets
        GET
        POST
        param_petId
          GET
            body
              petId
          PUT
            body
              petId
    zz
      GET
      DELETE
```

</details>

[Mermaid 라이브 에디터](https://mermaid.live/)에 붙여넣거나 문서에 포함하여 시각화할 수 있습니다.

{% mermaid() %}
mindmap
  root((API))
    GET
    about
      GET
      GET
      POST
        body
          data
          id
    gems
      GET
    gems_json
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        cookies
          cookie
        body
          query
          sort
    gems_yml
      GET
        cookies
          cookie
        body
          query
          sort
      PUT
        cookies
          cookie
        body
          query
          sort
    path_111
      PUT
    pets
      GET
        cookies
          cookie
        body
          query
          sort
      POST
        body
          name
      param_petId
        GET
          body
            petId
        PUT
          body
            breed
            name
            petId
    shards
      GET
    users
      POST
        body
          email
          name
      param_userId
        GET
          headers
            Authorization
          body
            userId
    v1
      pets
        GET
        POST
        param_petId
          GET
            body
              petId
          PUT
            body
              petId
    zz
      GET
      DELETE
{% end %}

## 팁

- 루트 노드는 항상 `API`로 표시됩니다.
- HTTP 메서드, 엔드포인트 경로 및 매개변수가 모두 마인드맵에 표현됩니다.
- 큰 API의 경우 Mermaid 호환 뷰어에서 브랜치를 축소하거나 확장할 수 있습니다.