+++
title = "한 번만 채우기: curl·컬렉션·probe에 같은 --pvalue"
description = "curl, Postman, OpenAPI, status-code probe, Burp/ZAP replay에 그대로 흘려보내는 파라미터 placeholder 한 세트."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

`noir scan ./app -f curl`을 한 번이라도 돌려봤다면 결과가 어떤지 아실 겁니다. `/users/{id}?limit=` 같은 줄이 길게 이어지죠. 앱의 지도로는 훌륭하지만, 그중 한 줄을 터미널에 붙여 넣어서 제대로 된 응답을 받을 수는 없습니다.

`-f postman`은 같은 빈칸을 다른 포장에 담은 것이고, `--probe`는 리터럴 `{id}`를 그대로 보내 404를 받거나, GET/HEAD/OPTIONS에 한해서만 `1`이나 `noir`를 슬쩍 채워 넣습니다. 결과를 받아 쓰는 쪽이 셋인데, 파라미터에 뭘 채울지는 셋이 제각각인 셈입니다.

`--pvalue`는 이걸 한 곳에서 정리합니다. 값을 한 번 선언하면 optimizer가 포맷터나 deliverer가 엔드포인트 목록을 보기 전에 모든 파라미터에 그 값을 심어둡니다.

## 플래그

반복해서 쓸 수 있습니다. 각 인자는 `TYPE=VALUE` 형태이고, 타입을 생략한 `VALUE`만 주면 모든 타입에 적용됩니다.

```bash
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  --pvalue "header=Authorization=Bearer replace-me"
```

| `TYPE` | 범위 |
| --- | --- |
| `any` (또는 타입 생략) | 모든 파라미터 타입 |
| `query` / `form` / `json` / `header` / `cookie` / `path` | 해당 버킷만 |

`VALUE`는 두 가지 형태가 있습니다.

| 형태 | 동작 |
| --- | --- |
| `42` | 대상 타입의 모든 파라미터 |
| `id=42` 또는 `id:42` | 이름이 `id`인 파라미터만 |

치환은 엔드포인트 목록을 정리하는 단계에서 일어나기 때문에 curl, HTTPie, PowerShell, OpenAPI, Postman, JSON, YAML 출력은 물론 probe와 export보다도 앞섭니다. 출력 형식 쪽은 [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.ko.md), probe 쪽은 [결과 전달](@/usage/more_features/deliver/index.ko.md) 문서를 참고하세요.

## 규칙이 고르는 방식

타입 전용 규칙이 전역 `any` 규칙보다 우선합니다. 그래서 path 파라미터에서는 `--pvalue path=…`가 타입 없는 `--pvalue test`를 이깁니다. 같은 타입 안에서는 이름을 지정한 규칙이 catch-all보다 우선하고, 플래그를 적은 순서는 상관없습니다.

```bash
# limit → 10, 나머지 query → 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=1" \
  --pvalue "query=limit=10"
```

두 줄을 뒤집어도 결과는 같습니다. 같은 이름에 규칙을 두 개 주면 먼저 적은 쪽이 이기지만, 그렇게 쓸 일은 거의 없을 겁니다.

## 같은 선언이 빛을 보는 세 곳

### 바로 붙여 넣을 수 있는 curl

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

`source`하면 끝입니다. curl 빌더가 내보내는 URL에는 path 템플릿이 이미 치환되어 있어서, 나중에 `{id}`를 `sed`로 고칠 필요가 없습니다.

### 팀을 위한 Postman / OpenAPI

```bash
noir scan ./api -f postman -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  --pvalue "header=Authorization=Bearer replace-me" \
  -o /tmp/api.postman.json

noir scan ./api -f oas3 -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "query=limit=10" \
  -o /tmp/api.openapi.json
```

curl 때와 같은 `--pvalue` 블록입니다. 리뷰어는 컬렉션 하나를 import하고, CI는 어제의 OpenAPI와 diff하고, 출력 형식이 달라져도 placeholder는 그대로입니다.

### 라이브 status code, 필요하면 proxy까지

```bash
# 관측된 status code를 붙이고, 뻔한 miss는 버립니다
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# 타깃 부하를 두 배로 늘리지 않도록 read 요청만 Burp/ZAP로
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes`, `--probe`, `--probe-via`는 모두 `-u`가 필요합니다.

probe 전에 하나 알아두면 좋은 게 있습니다. `--pvalue path=…`가 없으면 Noir는 read-only verb(GET, HEAD, OPTIONS)에만 `1`이나 `noir`로 path 파라미터를 자동으로 채웁니다. POST, PUT, PATCH, DELETE는 리터럴 템플릿을 유지해서, 실수로 `DELETE /users/1`이 나가는 일이 없습니다. 명시적으로 `--pvalue path=id=42`를 주면 이 보호가 풀리고 write를 포함한 모든 verb에 적용됩니다. 의도한 거라면 괜찮고, 아니라면 준비될 때까지 `--probe-skip "POST"`나 `--probe-skip "DELETE"`로 write를 빼두세요.

## 기본값은 설정 파일에

같은 키를 설정 파일에도 쓸 수 있어서, CI 잡마다 플래그를 반복할 필요가 없습니다.

```yaml
url: "https://staging.example.com"
format: "json"
status_codes: true
exclude_codes: "404,502"
set_pvalue_path:
  - "id=42"
  - "slug=demo"
set_pvalue_query:
  - "limit=10"
  - "1"
set_pvalue_header:
  - "X-Debug-Tenant=noir-ci"
```

```bash
noir config init
noir scan ./api --config-file ./ci/noir.yaml
```

일회성으로 다른 id가 필요하면 CLI의 `--pvalue`가 설정 파일을 이깁니다. [설정 파일](@/usage/configurations/configuration_file/index.ko.md)과 [`noir config`](@/usage/cli_commands/_index.ko.md#config) 문서를 참고하세요.

## 자주 걸리는 지점

- **이름 없는 파라미터는 값을 받지 못합니다.** analyzer가 파라미터의 존재는 알지만 이름을 모르면 `--pvalue`가 돌기 전에 빠집니다. curl 출력에 뜬금없는 `=42`가 생기지는 않습니다.
- **`body`는 `json`으로 들어갑니다.** `body`로 기록된 파라미터는 optimizer가 아는 버킷으로 정규화되기 때문에 `--pvalue json=…`이 닿습니다. 새 스크립트에서는 옛 `--set-pvalue-*` 별칭보다 `--pvalue TYPE=VAL`을 쓰세요.
- **헤더는 `-u`를 따릅니다.** `--probe-header`와 probe payload용 `--pvalue header=…`는 `-u`로 지정한 호스트를 향합니다. 소스에 absolute host가 이미 박힌 엔드포인트는 그 host를 유지하고 이 헤더를 받지 않습니다. 직접 지정한 export 목적지는 헤더를 그대로 받습니다.
- **시크릿은 커밋하지 마세요.** `ci/noir.yaml`에 토큰을 넣지 말고 CI에서 env로 펼치세요 (`--pvalue "header=Authorization=Bearer $TOKEN"`).

## 정리

값이 없는 discovery 결과는 번지 없는 지도입니다. `--pvalue`로 한 번 번지를 매기면 curl, 컬렉션, OpenAPI, status-code 필터, proxy replay에 같은 값을 그대로 쓸 수 있습니다. probe할 때 write verb는 신중하게 다루고, 팀이 placeholder에 합의했다면 설정 파일로 옮기세요.
