+++
title = "Mermaid 차트"
description = "Noir 스캔 결과에서 API 구조를 시각화하는 Mermaid 마인드맵을 생성합니다."
weight = 5
sort_by = "weight"

+++

API 엔드포인트를 [Mermaid 마인드맵](https://mermaid.js.org/syntax/mindmap.html)으로 그려서 전체 API 구조를 한눈에 볼 수 있습니다.

## 사용법

```bash
noir scan . -f mermaid
```

## 출력 예제

마인드맵은 트리 구조입니다. 루트 노드는 API 전체, 가지는 URL 경로 세그먼트이며, 각 HTTP 메서드는 자신이 담당하는 경로 아래에 놓입니다. 메서드 아래 파라미터는 요청에서 실리는 위치별로 `headers`, `cookies`, `query`, `body`(JSON과 form 필드), `path` 그룹으로 나뉩니다. 경로 파라미터는 `param_*` 가지로도 표시되며(`/users/{user_id}` → `param_user_id` 세그먼트), WebSocket 경로에는 `websocket` 태그가 붙습니다. 이름은 Mermaid에서 안전하게 바뀝니다. 문자, 숫자, `_`가 아닌 글자는 `_`가 되고, 숫자로 시작하는 이름에는 `path_`가 앞에 붙습니다(`x-api-key` → `x_api_key`, `/1.html` → `path_1_html`).

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

출력을 [Mermaid 라이브 에디터](https://mermaid.live/)에 붙여넣으면 바로 렌더링됩니다. Markdown 파일에 넣어도 GitHub, GitLab, Notion에서 렌더링됩니다.

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
