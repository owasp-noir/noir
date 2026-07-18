+++
title = "Mermaid 차트"
description = "Noir 스캔 결과에서 API 구조를 시각화하는 Mermaid 마인드맵을 생성합니다."
weight = 5
sort_by = "weight"

+++

API 엔드포인트를 [Mermaid 마인드맵](https://mermaid-js.github.io/mermaid/#/mindmap)으로 시각화하여 전체 API 구조를 한눈에 파악할 수 있습니다.

## 사용법

```bash
noir scan . -f mermaid
```

## 출력 예제

마인드맵은 트리 구조입니다. 루트 노드는 API 전체, 가지는 URL 경로 세그먼트이며, 각 HTTP 메서드는 자신이 담당하는 경로 아래에 놓입니다. 메서드 아래 파라미터는 요청에서 전달되는 위치별로 `query`, `body`, `headers`, `cookies`, `path` 그룹으로 나뉩니다. 경로 파라미터는 `param_*` 가지로도 표시되며(`/users/{user_id}` → `param_user_id` 세그먼트), WebSocket 경로에는 `websocket` 태그가 붙습니다.

<details>
    <summary>Mermaid 출력</summary>

```
mindmap
  root((API))
    GET
    account
      GET
        headers
          authorization
        cookies
          session
    search
      GET
        query
          page
          q
    users
      POST
        body
          email
          name
      param_user_id
        GET
          query
            verbose
          path
            user_id
        DELETE
          path
            user_id
    ws
      feed
        GET websocket
```

</details>

출력 결과를 [Mermaid 라이브 에디터](https://mermaid.live/)에 붙여넣으면 바로 렌더링됩니다. Markdown 파일에 직접 삽입해도 GitHub, GitLab, Notion 등에서 네이티브로 렌더링해줍니다.

{% mermaid() %}
mindmap
  root((API))
    GET
    account
      GET
        headers
          authorization
        cookies
          session
    search
      GET
        query
          page
          q
    users
      POST
        body
          email
          name
      param_user_id
        GET
          query
            verbose
          path
            user_id
        DELETE
          path
            user_id
    ws
      feed
        GET websocket
{% end %}

## 팁

- API 규모가 크다면 Mermaid 호환 뷰어에서 가지를 접거나 펼칠 수 있습니다.
