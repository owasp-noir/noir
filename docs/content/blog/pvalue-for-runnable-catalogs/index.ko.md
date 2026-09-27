+++
title = "한 번만 채우기: curl·컬렉션·probe에 같은 --pvalue"
description = "curl, Postman, OpenAPI, status-code probe, Burp/ZAP replay에 그대로 흘려보내는 파라미터 placeholder 한 세트."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

Noir의 본업은 discovery다. 라우트와 메서드, 파라미터를 찾는다. 그런데 그 결과를 그대로 붙여 넣어 실제 서버에 때릴 수 있는 *값*까지는 만들어 주지 않는다.

이 빈칸은 plain 출력을 떠나자마자 드러난다. `-f curl`은 `/users/{id}`와 빈 쿼리를 찍고, `-f postman`은 필드가 비어 있는 컬렉션을 만들고, `--probe`는 리터럴 템플릿에 404를 맞거나(또는 read-only verb에 한해) `1` / `noir`로 슬쩍 채운다. 같은 파라미터인데 consumer마다 이야기가 다르다.

`--pvalue`가 그 간극을 메운다. placeholder를 한 번 선언하면 optimizer가 포맷터·deliverer보다 먼저 모든 param에 값을 쓴다. 한 번의 스캔, 같은 값, 모든 sink.

## --pvalue가 실제로 하는 일

플래그는 반복 가능하다. 각 인자는 `TYPE=VALUE`이고, 타입을 생략한 bare `VALUE`는 모든 타입에 적용된다.

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

`VALUE` 자체도 두 형태다.

| 형태 | 동작 |
| --- | --- |
| `42` | 대상 타입의 모든 파라미터에 사용 |
| `id=42` 또는 `id:42` | 이름이 `id`인 파라미터에만 사용 |

optimizer는 엔드포인트 목록을 정리할 때, 출력 빌더와 probe/export보다 먼저 이 규칙을 적용한다. 그래서 같은 `--pvalue` 한 줄이 curl, HTTPie, PowerShell, OpenAPI, Postman, JSON/YAML, 라이브 probe에 동시에 먹힌다. 포맷 쪽은 [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.ko.md), probe 쪽은 [결과 전달](@/usage/more_features/deliver/index.ko.md)을 보면 된다.

## 규칙 순서가 결과를 가른다

매칭은 first-hit이다. 타입 안에서는 타입 전용 규칙이 전역 `any` 목록보다 먼저 검사되므로, `--pvalue path=…`가 bare `--pvalue test`보다 path 파라미터에서 이긴다.

다만 같은 타입 안에서는 catch-all이 *모든* 이름에 매칭된다. 이름 지정 오버라이드를 앞에 둬라.

```bash
# limit 은 10, 나머지 query 파라미터는 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=limit=10" \
  --pvalue "query=1"
```

두 줄을 뒤집으면 `limit`도 `1`이 된다. catch-all이 먼저 맞기 때문이다. catch-all을 앞에 둔 문서 예시는 이 matcher 기준으로는 잘못된 순서다. 이름 지정 규칙을 타입 기본값보다 앞에 두는 쪽이 안전하다.

## 선언 하나를 공유하는 세 가지 워크플로

### 1. 수동 triage용 runnable curl

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

파일을 붙여 넣거나 `source`하면 바로 쓸 수 있는 요청이 된다. path 템플릿은 curl 빌더가 내보내는 URL에 이미 치환되어 있어, 줄마다 `{id}`를 손으로 고치지 않아도 된다.

### 2. 팀용 Postman / OpenAPI

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

curl 때와 같은 `--pvalue` 블록이다. 리뷰어는 컬렉션 하나를 import하고, CI는 OpenAPI를 이전 커밋과 diff한다. 포맷이 바뀌어도 placeholder가 흔들리지 않는 것이 핵심이다.

### 3. status code로 라이브 검증 (필요하면 proxy replay)

```bash
# 관측된 status code를 붙이고, 뻔한 miss는 제거
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# 타깃 부하를 두 배로 늘리지 않고 Burp/ZAP로 read 트래픽만 흘린다
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes`와 `--probe` / `--probe-via`는 모두 `-u`가 필요하다. probe의 path 채움에는 추가 안전장치가 있다. `--pvalue path=…`가 없으면 Noir는 read-only verb(GET, HEAD, OPTIONS)에만 `1` / `noir`를 자동 채운다. POST/PUT/PATCH/DELETE는 리터럴 템플릿을 유지해서, 실수로 `DELETE /users/1`이 나가지 않게 한다. 명시적인 `--pvalue path=id=42`는 write를 포함한 모든 verb에 적용된다. 의도적으로 쓰거나, 준비가 될 때까지 `--probe-skip "POST"` / `--probe-skip "DELETE"`로 write를 막아 두라.

## 플래그를 붙여 넣지 않는 팀 기본값

같은 키를 설정 파일에 둘 수 있다. 공유 `ci/noir.yaml`에 프로젝트 placeholder 정책을 넣으면 된다.

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

일회성으로 다른 id가 필요하면 CLI `--pvalue`가 파일을 덮어쓴다. [설정 파일](@/usage/configurations/configuration_file/index.ko.md)과 [`noir config`](@/usage/cli_commands/_index.ko.md#config)를 참고하라.

## 기억할 만한 주의점

- **빈 이름은 값을 받지 않는다.** 파라미터 존재는 알지만 이름을 모르는 analyzer 결과는 `--pvalue` 전에 걸러진다. curl에 이상한 `=42`가 생기지 않는다.
- **`body` vs `json`.** `body`로 기록된 param은 optimizer가 이해하는 canonical 버킷으로 정규화되므로 `--pvalue json=…`가 도달한다. 새 스크립트에서는 옛 `--set-pvalue-*` alias보다 v1 `--pvalue TYPE=VAL` 형태를 써라.
- **다른 호스트의 헤더.** `--probe-header`(그리고 probe payload용 `--pvalue header=…`)는 `-u` 타깃용이다. 소스에 이미 absolute host가 찍혀 있던 엔드포인트는 그 host를 유지하며, `-u`를 겨냥한 probe 헤더는 빠진다. 사용자가 직접 지정한 export 목적지는 헤더를 그대로 받는다.
- **시크릿을 커밋하지 마라.** 토큰을 `ci/noir.yaml`에 넣기보다 CI에서 env로 펼친 플래그(`--pvalue "header=Authorization=Bearer $TOKEN"`)를 써라.

## 짧게 정리

값 없는 discovery는 번지 없는 지도다. `--pvalue`는 번지를 한 번 매기고 curl, 컬렉션, OpenAPI, status-code 필터, proxy replay에 같은 번호를 재사용하는 방법이다. catch-all보다 이름 지정 오버라이드를 앞에 두고, write verb는 명시적으로 다루며, 팀이 placeholder에 합의하면 설정 파일에 기본값을 두라.
