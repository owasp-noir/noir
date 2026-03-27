+++
title = "Mermaid 차트"
description = "Noir 스캔 결과에서 API 구조를 시각화하는 Mermaid 마인드맵을 생성합니다."
weight = 5
sort_by = "weight"

+++

API 엔드포인트를 [Mermaid 마인드맵](https://mermaid-js.github.io/mermaid/#/mindmap)으로 시각화하여 전체 API 구조를 한눈에 파악할 수 있습니다.

## 사용법

```bash
noir -b . -f mermaid
```

## 출력 예제

마인드맵은 트리 구조로 구성됩니다. 루트 노드가 API 전체를 나타내고, 가지가 URL 경로 세그먼트, 잎이 HTTP 메서드와 파라미터(타입별로 `body`, `headers`, `cookies`로 분류)입니다.

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

출력 결과를 [Mermaid 라이브 에디터](https://mermaid.live/)에 붙여넣으면 바로 렌더링됩니다. Markdown 파일에 직접 삽입해도 GitHub, GitLab, Notion 등에서 네이티브로 렌더링해줍니다.

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
- HTTP 메서드, 엔드포인트 경로, 파라미터가 모두 마인드맵에 표현됩니다.
- API 규모가 크다면 Mermaid 호환 뷰어에서 가지를 접거나 펼칠 수 있습니다.
