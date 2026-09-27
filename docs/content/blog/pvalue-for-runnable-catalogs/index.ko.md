+++
title = "한 번만 채우기: curl·컬렉션·probe에 같은 --pvalue"
description = "curl, Postman, OpenAPI, status-code probe, Burp/ZAP replay에 그대로 흘려보내는 파라미터 placeholder 한 세트."
date = "2026-09-27"
tags = ["tips", "pvalue", "curl", "probe", "workflow"]
authors = ["hak"]
template = "blog_post"
+++

`noir scan ./app -f curl`을 돌리면 `/users/{id}?limit=` 벽이 나온다. 지도로는 쓸 만하다. 요청으로는 못 쓴다.

`-f postman`은 같은 빈칸을 다른 봉투에 넣은 것이고, `--probe`는 리터럴 `{id}`에 404를 맞거나 GET/HEAD/OPTIONS에 한해 `1` / `noir`를 슬쩍 넣는다. sink 셋, 같은 파라미터에 대한 의견 셋.

`--pvalue`로 한 번에 정리한다. placeholder를 선언하면 optimizer가 포맷터·deliverer보다 *먼저* 모든 param에 값을 심는다. 스캔 한 번. 값 동일. sink 전부.

## 플래그

반복 가능. 각 인자는 `TYPE=VALUE`, 타입을 뺀 bare `VALUE`는 모든 타입에 먹힌다.

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

`VALUE`는 두 가지다.

| 형태 | 동작 |
| --- | --- |
| `42` | 대상 타입의 모든 파라미터 |
| `id=42` 또는 `id:42` | 이름이 `id`인 파라미터만 |

엔드포인트 목록을 정리하는 시점에 돌아간다. curl / HTTPie / PowerShell / OpenAPI / Postman / JSON / YAML과 probe/export보다 앞이다. 선언 하나, consumer 전부. 포맷: [cURL / HTTPie / PowerShell](@/usage/output_formats/curl/index.ko.md). probe: [결과 전달](@/usage/more_features/deliver/index.ko.md).

## 순서가 발목을 잡는다

매칭은 first-hit. 타입 전용 규칙이 전역 `any`보다 먼저라서, path에서는 `--pvalue path=…`가 bare `--pvalue test`를 이긴다.

같은 타입 안에서는 catch-all이 *모든* 이름에 걸린다. 이름 지정 오버라이드를 앞에 둬라.

```bash
# limit → 10, 나머지 query → 1
noir scan ./app -f curl -u https://api.example.com \
  --pvalue "query=limit=10" \
  --pvalue "query=1"
```

두 줄을 뒤집으면 `limit`도 `1`이다. catch-all이 먼저 맞았기 때문. catch-all을 앞에 둔 문서 예시는 이 matcher 기준으로는 틀린 순서다. 이름 지정 → 타입 기본값.

## 같은 선언, 세 곳에서 이득 보는 지점

### 바로 붙여 넣을 수 있는 curl

```bash
noir scan ./api -f curl -u https://staging.example.com \
  --pvalue "path=id=42" \
  --pvalue "path=slug=demo" \
  --pvalue "query=1" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN" \
  -o /tmp/api.curl.sh
```

`source`하면 끝. path 템플릿은 curl 빌더가 내보내는 URL에 이미 치환돼 있다. `{id}`를 줄마다 고칠 일 없다.

### 팀용 Postman / OpenAPI

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

curl 때와 같은 `--pvalue` 블록. 리뷰어는 컬렉션 하나 import, CI는 어제 OpenAPI랑 diff. 포맷이 바뀌어도 placeholder는 안 흔들린다.

### status code로 라이브 검증, 필요하면 proxy replay

```bash
# 관측된 코드 붙이고, 뻔한 miss는 버림
noir scan ./api -u https://staging.example.com \
  --status-codes --exclude-codes 404,502 \
  --pvalue "path=id=42" \
  --pvalue "query=1" \
  -f json -o /tmp/live.json

# 타깃 부하를 두 배로 안 늘리고 Burp/ZAP로 read 트래픽만
noir scan ./api -u https://staging.example.com \
  --probe-via http://127.0.0.1:8080 \
  --probe-match "GET" \
  --pvalue "path=id=42" \
  --pvalue "header=Authorization=Bearer $STAGING_TOKEN"
```

`--status-codes`, `--probe`, `--probe-via` 전부 `-u`가 필요하다.

probe path 채움엔 나중에 뼈아픈 안전장치가 있다. `--pvalue path=…`가 없으면 read-only(GET, HEAD, OPTIONS)에만 `1` / `noir`를 자동으로 넣는다. POST / PUT / PATCH / DELETE는 리터럴 템플릿을 유지해서, 실수로 `DELETE /users/1`이 나가지 않는다. 명시적 `--pvalue path=id=42`는 write를 포함한 *모든* verb에 적용된다. 의도적으로 쓰거나, 준비될 때까지 `--probe-skip "POST"` / `--probe-skip "DELETE"`로 write를 막아 둬라.

## 기본값은 설정 파일에

같은 키, CI마다 플래그 붙여 넣기 없음:

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

일회성으로 다른 id가 필요하면 CLI `--pvalue`가 이긴다. [설정 파일](@/usage/configurations/configuration_file/index.ko.md) · [`noir config`](@/usage/cli_commands/_index.ko.md#config).

## 여기서 자주 밟는다

- **이름 없는 param은 값을 못 받는다.** 구멍은 알지만 이름을 모르는 analyzer 결과는 `--pvalue` 전에 빠진다. curl에 이상한 `=42`는 안 생긴다.
- **`body`는 `json`으로 들어간다.** `body`로 기록된 param은 optimizer가 아는 버킷으로 정규화되니 `--pvalue json=…`가 닿는다. 새 스크립트에선 옛 `--set-pvalue-*`보다 v1 `--pvalue TYPE=VAL`을 써라.
- **헤더는 `-u`를 따른다.** `--probe-header`와 probe payload용 `--pvalue header=…`는 `-u` 타깃용이다. 소스에 absolute host가 이미 찍힌 엔드포인트는 그 host를 유지하고, `-u`용 probe 헤더는 빠진다. 직접 지정한 export 목적지는 헤더를 그대로 받는다.
- **시크릿은 커밋하지 마라.** CI에서 env로 펼쳐라 (`--pvalue "header=Authorization=Bearer $TOKEN"`). `ci/noir.yaml`에 토큰 넣지 말고.

## 정리

값 없는 discovery는 번지 없는 지도다. `--pvalue`로 한 번 매기고 curl, 컬렉션, OpenAPI, status-code 필터, proxy replay에 같은 번호를 써라. catch-all보다 이름 지정 오버라이드를 앞에. write verb는 의도적으로. 팀이 placeholder에 합의하면 설정 파일에 기본값을.
