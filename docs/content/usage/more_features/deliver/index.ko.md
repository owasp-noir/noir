+++
title = "다른 도구로 결과 전송하기"
description = "Burp/ZAP을 통해 endpoint를 probe하거나 Elasticsearch로 export 합니다."
weight = 1
sort_by = "weight"

+++

Noir의 결과 전송은 성격이 다른 두 family로 나뉘어 있어요.

- **PROBE** — discovered endpoint를 실제 HTTP 요청으로 쏴봅니다 (active replay, 필요 시 Burp Suite나 ZAP 같은 proxy를 경유).
- **EXPORT** — endpoint 카탈로그를 Elasticsearch 같은 외부 스토어로 data 형태로 적재합니다. endpoint 자체에는 HTTP 트래픽이 가지 않아요.

## Probe

관련 플래그:

| Flag | 용도 |
| --- | --- |
| `--probe` | 각 endpoint에 HTTP 요청을 발사 (`-u` 필요) |
| `--probe-via URL` | proxy URL을 거쳐 probe |
| `--probe-header VAL` | probe마다 헤더 추가 (반복 가능) |
| `--probe-match VAL` | 패턴에 매칭되는 endpoint만 probe (URL / method / `method:URL`) |
| `--probe-skip VAL` | 패턴에 매칭되는 endpoint를 제외 |

### Replay through proxy

로컬 Burp/ZAP proxy로 모든 endpoint를 흘려보내서 scanner가 처리하도록 합니다.

```bash
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080
```

![](./deliver-proxy.png)

### Custom headers

인증 토큰 등 커스텀 헤더를 매 probe에 붙입니다.

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-header "Authorization: Bearer your-token"
```

![](./deliver-header.png)

### Match / skip

proxy로 흘려보낼 endpoint를 좁힐 수 있어요. 패턴은 URL 부분 문자열, HTTP 메서드(대소문자 무시), 또는 `method:URL` 조합을 받습니다.

```bash
# API endpoint만
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "api"

# GET 요청만
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "GET"

# POST 요청 제외
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-skip "POST"

# /api 경로의 POST만
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "POST:/api"

# /admin 경로의 GET 제외
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-skip "GET:/admin"
```

지원 메서드: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT.

`--probe-match`와 `--probe-skip`은 여러 번 지정 가능합니다.

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-match "GET" --probe-match "POST:/api"
```

![](./deliver-mf.png)

## Export

Endpoint 카탈로그를 외부 스토어로 push 합니다. probe와는 성격이 다르므로 endpoint 자체에 트래픽이 가진 않아요.

```bash
noir scan ./source --export-es http://localhost:9200
```

## v0 aliases

v0.x flag 이름은 그대로 작동합니다. Noir 내부에서 silent하게 매핑해줘요.

| v0 flag | v1 등가 |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--send-es URL` | `--export-es URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |

v0 flag를 쓰던 기존 CI 스크립트, Dockerfile은 그대로 두면 됩니다. 새 문서, 예제, shell completion은 v1 이름을 노출합니다.
