+++
title = "다른 도구로 결과 전송하기"
description = "Burp/ZAP을 통해 endpoint를 probe하거나, Elasticsearch 또는 webhook으로 export 합니다."
weight = 1
sort_by = "weight"

+++

Noir의 결과 전송은 성격이 다른 두 family로 나뉩니다.

- **PROBE**: discovered endpoint를 실제 HTTP 요청으로 쏴봅니다 (active replay, 필요 시 Burp Suite나 ZAP 같은 proxy를 경유).
- **EXPORT**: endpoint 카탈로그를 외부 스토어(Elasticsearch, OpenSearch, 또는 임의의 webhook 리시버)로 data 형태로 적재합니다. endpoint 자체에는 HTTP 트래픽이 가지 않습니다.

{% mascot(mood="run") %}
Probe는 재전송, Export는 적재. 결과가 어디로 가야 하는지에 맞춰 고르면 돼.
{% end %}

## Probe

관련 플래그:

| Flag | 용도 |
| --- | --- |
| `--probe` | 각 endpoint에 HTTP 요청을 발사 (`-u` 필요) |
| `--probe-via URL` | proxy URL을 거쳐 probe |
| `--probe-header VAL` | probe마다 헤더 추가 (반복 가능) |
| `--probe-match VAL` | 패턴에 매칭되는 endpoint만 probe (URL / method / `method:URL`) |
| `--probe-skip VAL` | 패턴에 매칭되는 endpoint를 제외 |

`--probe`와 `--probe-via`는 서로 독립적입니다. 둘을 함께 주면 모든 endpoint에 요청이 두 번 나갑니다(proxy 경유 1회 + 직접 1회). 타깃 부하가 2배가 되므로, proxy에만 트래픽을 넣고 싶으면 `--probe-via`만 주세요.

### Path template

`/users/{id}` 같은 route는 그대로 요청할 수 없으므로, noir가 probe 전에 placeholder를 채웁니다. 단 **read-only verb에만** 적용합니다(GET, HEAD, OPTIONS). 숫자로 보이는 이름(`id`, `page`, `*_id` 등)은 `1`, 나머지는 `noir`가 들어갑니다.

POST, PUT, PATCH, DELETE는 template을 그대로 둡니다. 여기서 채우면 무해한 404가 실제 쓰기로 바뀌기 때문입니다 — 살아있는 레코드에 `DELETE /users/1`이 나갑니다. proxy 경유 시 template 그대로 도착하므로, 필요하면 직접 수정해서 replay 하면 됩니다.

값을 직접 지정하려면 `--pvalue path=...`를 쓰세요. 이쪽은 모든 verb에 적용됩니다.

```bash
noir scan ./source -u http://localhost:3000 --probe --pvalue path=id=42
```

리포트 출력은 항상 원래 template을 유지합니다. 실제로 나가는 요청만 구체화됩니다.

### Replay through proxy

로컬 Burp/ZAP proxy로 모든 endpoint를 흘려보내서 scanner가 처리하도록 합니다.

```bash
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080
```

proxy 포트는 필수입니다. `--probe-via http://localhost`는 추측하지 않고 거부합니다. 포트 없는 proxy URL은 라우팅할 수 없고, 그대로 두면 probe가 proxy를 건너뛰고 타깃으로 직접 나가기 때문입니다. `curl -x`가 받는 형태인 `host:port`는 그대로 받아 `http://host:port`로 해석합니다.

<img src="./deliver-proxy.png" alt="Noir가 발견한 엔드포인트 4개를 localhost:8090 프록시로 보내고, 프록시의 히스토리 탭에 요청 4건이 도착한 모습." width="1534" height="392" loading="lazy" decoding="async">

### Custom headers

인증 토큰 등 커스텀 헤더를 매 probe에 붙입니다.

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-header "Authorization: Bearer your-token"
```

<img src="./deliver-header.png" alt="인터셉트 프록시에 잡힌 요청. Noir가 추가하도록 지정한 Abcd 와 X-API-Key 헤더가 함께 실려 있다." width="1136" height="460" loading="lazy" decoding="async">

이 헤더는 `-u` 타깃에만 붙습니다. 대부분의 endpoint는 noir가 `-u`에 이어붙인 경로지만, 소스에 이미 scheme과 host가 적혀 있던 endpoint(OAS `servers:` 항목, HAR 캡처, 호스팅 백엔드 URL)는 그 host를 그대로 유지하며, 그 host는 지금 스캔 중인 코드에서 온 값입니다. 이런 endpoint도 probe는 그대로 나가지만 사용자의 헤더는 실리지 않고, 어떤 host에서 빠졌는지 한 번 알려줍니다.

```
▲ Probe: --probe-header values withheld from https://collector.example.com — it is not the --url target.
```

export 대상(`--export-es`, `--export-webhook`)은 영향을 받지 않습니다. 그 host는 사용자가 직접 지정한 것이므로 `--probe-header`가 그대로 인증에 쓰입니다.

### Match / skip

proxy로 흘려보낼 endpoint를 좁힐 수 있습니다. 패턴은 URL 부분 문자열, HTTP 메서드(대소문자 무시), 또는 `method:URL` 조합을 받습니다.

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

지원 메서드: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT, QUERY.

`--probe-match`와 `--probe-skip`은 여러 번 지정 가능합니다.

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-match "GET" --probe-match "POST:/api"
```

<img src="./deliver-mf.png" alt="Noir가 엔드포인트 11개를 찾았지만, 매처 2개를 지정해 POST /update 와 GET /socket 만 프록시로 전달한 모습." width="1242" height="493" loading="lazy" decoding="async">

## Export

Endpoint 카탈로그를 외부 스토어로 push 합니다. probe와는 성격이 다르므로 endpoint 자체에 트래픽이 가지 않습니다.

| Flag | 용도 |
| --- | --- |
| `--export-es URL` | 카탈로그를 Elasticsearch에 색인 |
| `--export-opensearch URL` | OpenSearch용. 이 요청 형태에 대해서는 wire protocol이 동일합니다 |
| `--export-webhook URL` | 카탈로그를 단일 JSON 문서로 임의의 HTTP 리시버에 POST |

### Elasticsearch / OpenSearch

document endpoint를 전체 경로로 넘겨야 합니다. Noir는 넘겨준 URL 그대로 POST 하며, index나 `_doc` 경로를 알아서 붙이지 않습니다.

```bash
noir scan ./source --export-es http://localhost:9200/noir/_doc
```

포트를 생략한 `http://` URL은 9200으로 기본 설정됩니다. 포트를 생략한 `https://` URL은 scheme 기본값(443)을 그대로 씁니다. managed cluster(AWS OpenSearch Service, Elastic Cloud)와 TLS reverse proxy가 443에서 listen하기 때문입니다.

인증은 `--probe-header`를 재사용합니다. 이름과 달리 이 헤더는 export 요청에도 붙습니다.

```bash
noir scan ./source --export-es https://my.cloud.es.io/noir/_doc \
  --probe-header "Authorization: ApiKey <base64-key>"
```

### Webhook

카탈로그 전체를 단일 JSON 문서로 POST 합니다.

```bash
noir scan ./source --export-webhook https://hooks.example.com/noir
```

body는 세 개의 field로 구성됩니다.

| Field | 내용 |
| --- | --- |
| `endpoints` | `-f json`이 출력하는 것과 동일한 배열 |
| `endpoint_count` | `endpoints`의 항목 수 |
| `noir_version` | 이 문서를 만든 noir 버전 |

Slack incoming webhook, Discord webhook endpoint, Zapier/n8n trigger, 사내 커스텀 리시버 모두 임의의 JSON body를 받으므로 하나의 계약으로 흔한 목적지를 커버합니다. 특정 플랫폼 형태(예: Slack의 `{"text": ...}` block)가 필요하면 noir가 플랫폼별 formatter를 갖는 대신 transformer를 경유하세요.

### TLS

probe와 export 모두 TLS 인증서를 검증합니다. self-signed 사내 호스트에는 `--tls-skip-verify`로 insecure context를 선택할 수 있습니다.

proxy delivery는 예외입니다. `--probe-via`는 항상 검증을 건너뜁니다. 인터셉트 proxy가 자체 인증서를 제시하므로, 그러지 않으면 replay되는 모든 요청이 handshake에서 실패합니다.

## v0 aliases

v0.x flag 이름은 그대로 작동합니다. Noir가 내부에서 조용히 매핑합니다.

| v0 flag | v1 등가 |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--send-es URL` | `--export-es URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |

v0 flag를 쓰던 기존 CI 스크립트, Dockerfile은 그대로 두면 됩니다. 새 문서, 예제, shell completion은 v1 이름을 노출합니다.
