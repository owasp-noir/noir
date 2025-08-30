+++
title = "Mermaid 차트"
description = "Mermaid 출력 형식을 사용하여 Noir 스캔 결과에서 대화형 API 마인드맵을 생성하는 방법을 알아보세요. 이는 API 구조를 시각화하고 팀과 공유하는 강력한 방법입니다."
weight = 5
sort_by = "weight"

[extra]
+++

Mermaid 출력 형식을 사용하면 API 엔드포인트를 대화형 마인드맵으로 시각화할 수 있습니다. 이는 API 구조를 빠르게 이해하고, 사용 가능한 엔드포인트를 식별하며, 팀과 상위 수준의 개요를 공유하는 데 특히 유용합니다.

Noir는 코드베이스 분석에서 직접 [Mermaid 마인드맵](https://mermaid-js.github.io/mermaid/#/mindmap)을 생성할 수 있습니다.

## Mermaid 마인드맵 생성 방법

Mermaid 마인드맵을 생성하려면 `-f` 또는 `--format` 플래그를 `mermaid`와 함께 사용하세요:

```bash
noir -b . -f mermaid
```

이렇게 하면 Mermaid 라이브 에디터, 문서 또는 호환 도구에 복사하여 붙여넣을 수 있는 Mermaid 마인드맵 정의가 출력됩니다.

## Mermaid 출력 예제

`mermaid` 형식 출력의 샘플입니다:

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

이 마인드맵을 [Mermaid 라이브 에디터](https://mermaid.live/)에 출력을 붙여넣거나 문서에 포함하여 시각화할 수 있습니다.

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

## Mermaid 마인드맵을 사용하는 이유는?

- **API 구조**를 한눈에 **시각화**
- 팀이나 이해관계자와 **엔드포인트 맵 공유**
- **누락되거나 중복된 엔드포인트를 빠르게 발견**
- **문서와 통합**: Mermaid는 많은 문서 도구에서 지원됩니다

## 팁

- 명확성을 위해 루트 노드는 항상 `API`로 라벨이 지정됩니다.
- HTTP 메서드(GET, POST 등), 엔드포인트 경로 및 매개변수가 모두 마인드맵에 표현됩니다.
- 큰 API의 경우 Mermaid 호환 뷰어에서 쉬운 탐색을 위해 브랜치를 축소하거나 확장할 수 있습니다.

Mermaid 출력을 사용하면 Noir 스캔 결과를 즉시 API 표면의 시각적이고 탐색 가능한 맵으로 변환할 수 있습니다.