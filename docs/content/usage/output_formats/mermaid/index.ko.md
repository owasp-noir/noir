+++
title = "Mermaid 차트"
description = "Noir 스캔 결과에서 API 구조를 시각화하는 Mermaid 마인드맵을 생성합니다."
weight = 5
sort_by = "weight"

+++

찾은 엔드포인트를 [Mermaid 마인드맵](https://mermaid.js.org/syntax/mindmap.html)으로 그려 API 구조를 한눈에 봅니다.

## 사용법

```bash
noir scan . -f mermaid
```

## 출력 예제

마인드맵은 트리 구조입니다. 루트 노드는 API 전체, 가지는 URL 경로 세그먼트이며, 각 HTTP 메서드는 그 메서드를 받는 경로 아래에 달립니다. 메서드 아래 파라미터는 요청에서 실리는 위치별로 `headers`, `cookies`, `query`, `body`(JSON과 form 필드), `path` 그룹으로 나뉩니다. 경로 파라미터는 `param_*` 가지로도 표시되며(`/users/{user_id}` → `param_user_id` 세그먼트), WebSocket 경로에는 `websocket` 태그가 붙습니다. 이름은 Mermaid가 처리할 수 있게 바꿉니다. 문자, 숫자, `_`가 아닌 글자는 `_`가 되고, 숫자로 시작하는 이름에는 `path_`가 앞에 붙습니다(`x-api-key` → `x_api_key`, `/1.html` → `path_1_html`).

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

## 프로젝트 간 서비스 그래프

모노레포를 `--ai-context`로 스캔하면 정적으로 읽을 수 있는 외부 HTTP 호출을
다른 프로젝트의 라우트와 연결합니다. 호출 정보가 있으면 Mermaid는 mindmap
대신 프로젝트별 `flowchart LR`을 출력합니다.

```bash
noir scan ./monorepo --ai-context -f mermaid
noir trace "GET /checkout" ./monorepo
```

`trace`는 연결 후보를 너비 우선으로 탐색하며 순환 경로는 한 번씩 방문합니다.
JSON/YAML의 `calls`에는 원래 sink, 대상 URL·메서드·라우트 후보가,
`called_by`에는 호출자와 호출 위치가 기록됩니다. 빈 `matches`는 일치하는
라우트가 없다는 뜻이며, URL이 없으면 대상을 정적으로 읽지 못한 경우입니다.
`matched_by`는 `path_pattern`, `path_template`, `url_exact`처럼 연결 근거를
구분합니다. 서비스가 모호하면 후보를 모두 보존합니다. 요청 조건이 다른
동일 URL 라우트는 `service_variant` 식별자로 구분하여 저장된 보고서에서도
각 라우트의 후속 호출을 탐색할 수 있습니다.

이는 정적 후보이며 실행 결과나 데이터 흐름의 증명이 아닙니다. 경로 일치만으로
호스트를 확정하지 않습니다. 양쪽 URL에 호스트가 있으면 일치해야 하며,
서로 다른 비어 있지 않은 `details.project`가 필요합니다. 클라이언트 stub,
비 HTTP 진입점, 모든 경로를 받는 catch-all만으로는 연결하지 않습니다.
실제 대상 서비스에 요청을 보내지 않습니다.

`fetch`, `axios`, `requests`/`httpx`, Go의 `http.Get`/`http.Post` 등 URL을
첫 인자로 받는 호출을 지원합니다. 단순 문자열 결합과 JavaScript template,
Python f-string의 치환값은 경로의 전체 세그먼트로 취급합니다. 임의 표현식,
옵션 객체의 URL, 알 수 없는 base URL 및 설정·환경변수는 미해결 상태로
남습니다. Fetch 메서드는 기본 호출 또는 단일 리터럴 `method` 옵션일 때만
확정하며, 복잡한 옵션은 메서드를 미정으로 남겨 호환 라우트 후보를 보존합니다.
