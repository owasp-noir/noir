+++
title = "alibi: 알리바이를 대지 못하는 엔드포인트"
description = "Noir를 관점별로 한 번씩 돌려 code, doc, traffic, gateway, infra를 서로 대질시키는 동반 도구."
date = "2026-08-30"
tags = ["alibi", "release", "tooling"]
authors = ["hahwul"]
template = "blog_post"
+++

alibi를 공개합니다. Noir를 공격 표면의 관점별로 한 번씩 돌리고, 그 결과들을 서로 대질시키는 동반 도구입니다. [owasp-noir/alibi](https://github.com/owasp-noir/alibi)에 있습니다.

전제는 한 문단이면 충분합니다. Noir는 같은 표면을 다섯 방향에서 읽습니다.

| 관점 | 읽는 대상 |
| --- | --- |
| **code** | 33개 언어, 200개 이상의 분석기 |
| **doc** | OpenAPI, RAML, WSDL, GraphQL SDL, AsyncAPI, gRPC, Smithy, TypeSpec, OData, OpenRPC |
| **traffic** | HAR, mitmproxy, Burp, Caido, ZAP, Postman, Insomnia, Bruno, `.http` |
| **gateway** | nginx, Apache, Envoy, Kong, Traefik, APISIX, Caddy, Istio, 쿠버네티스 Ingress/Gateway API |
| **infra** | Terraform, CloudFormation, CDK, Serverless, Vercel, Netlify, Wrangler, Azure Functions, Kamal |

각 관점은 "무엇이 존재하는가"에 대한 하나의 진술입니다. 코드는 "이 라우트는 구현되어 있다"고 말하고, 계약은 "이 엔드포인트는 약속되어 있다"고 말하고, 캡처 파일은 "이 URL은 실제 요청을 받았다"고 말합니다. 한 관점에 나타난 엔드포인트라면 다른 관점에서도 자기 존재를 해명할 수 있어야 하고, 못 한다면 누군가 들여다봐야 합니다. 그 간극이 shadow API고, phantom 계약이고, 아무 데도 닿지 않는 게이트웨이 룰이죠. Noir는 다섯 진술을 수집하는 데서 멈춥니다. 의도된 설계입니다. alibi는 그 진술들이 서로 맞는지를 묻습니다.

## 한 번 스캔하면 될 줄 알았다

처음 계획은 스캔 한 번이었습니다. Noir가 어차피 모든 엔드포인트에 찾아낸 기술을 붙여주니, JSON 하나에서 다섯 관점이 공짜로 갈라져 나올 거라 생각했거든요.

안 갈라집니다. Noir는 모든 분석기에 걸쳐 `(method, url)`로 중복을 제거하는데, 탐지 도구로서는 맞는 설계입니다. 같은 표기의 Flask 라우트와 OpenAPI 경로는 실제로 하나의 엔드포인트니까요. 그런데 대조에는 치명적이고, 하필 최악의 방향으로 치명적입니다. 두 관점이 잘 일치할수록 더 많은 엔드포인트가 하나의 레코드로 합쳐지고, 그만큼 교차 검증의 근거가 사라집니다. casdoor를 통째로 스캔하면 코드 372개에 문서 9개. `swagger/` 디렉터리만 스캔하면 스펙에 235개가 들어 있습니다.

그래서 alibi는 `--only-techs`로 관점당 한 번씩 Noir를 돌리고, 조인은 직접 합니다. 이걸 위해 Noir를 고칠 일은 없었고, alibi가 직접 파싱하는 API 포맷도 없습니다. 입력은 오직 Noir의 JSON입니다.

별도 저장소인 이유, 그리고 Python인 이유도 여기 있습니다. Noir는 1년 남짓 사이 19k줄에서 198k줄이 됐습니다. 바이너리를 계속 키우는 것보다 생태계를 옆으로 넓히는 편이 낫고, 대조 도구의 기여 장벽은 낮을수록 좋으니까요.

## 돌리면 이렇게 나옵니다

```console
$ alibi scan ./casdoor
alibi  ·  1 source  ·  377 endpoints

  code 372   doc 235

  230 corroborated -- vouched for by more than one view

  19 endpoints nearly matched another view -- these may be matching failures, not real gaps

SHADOW  Shadow API -- Implemented, but no contract describes it
  134 findings  ·  4 critical, 57 high, 62 medium, 11 low

  critical POST    /api/upload-groups        router.go:87
           upload paths carry more consequence than reads
  critical POST    /api/upload-permissions   router.go:208
```

규칙은 여덟 개입니다. `SHADOW`, `PHANTOM`, `ORPHAN`, `LIVE_UNDOC`, `DANGLING`, `DRIFT`, `UNEXPOSED`, `COLD`. 심각도는 Noir의 tagger가 그 엔드포인트에서 본 것에 따라 움직입니다. 파일 업로드, 개인정보, 상태를 바꾸는 메서드, 인증의 흔적 같은 것들이요.

## 대부분의 작업은 대조가 아니었다

엔드포인트 목록 다섯 개를 조인하는 건 주말 프로젝트입니다. 진짜 작업은 리포트가 거짓말을 못 하게 만드는 쪽이었고, alibi의 가드 하나하나는 전부 실제 저장소가 먼저 틀린 답을 자신 있게 내놓아서 생겼습니다.

casdoor 첫 전체 실행에서는 finding의 절반 가까이가 critical로 떴습니다. 승격 조건이 "인증의 흔적 없음"이었는데, Noir의 인증 tagger가 400개 가까운 엔드포인트 중 9개에만 태그를 달았으니 "흔적 없음"은 거의 어디서나 참이었고, 그래서 아무 의미도 없었습니다. 지금은 규칙이 반대로 돕니다. 신호의 존재가 심각도를 움직이고, 태그 부재에 반응하는 조정은 그 태그가 스캔 어딘가에 존재할 때만 적용됩니다.

Argo CD는 shadow API 58개에 phantom 계약 198개로 나왔는데 전부 허상이었습니다. Go 코드는 `/api` 하나를 등록하고, OpenAPI는 그 아래 198개 경로를 기술합니다. 같은 표면, 두 개의 입도, 겹치는 엔드포인트는 0. 인구가 있는 두 관점의 겹침이 0이면 이제 "대조가 실패했다"로 읽습니다. 규칙을 보류하고, finding을 쏟아내는 대신 이유를 출력합니다.

NetBox는 하마터면 최악의 답을 내보낼 뻔했습니다. API 문서가 12.35MB짜리 OpenAPI 파일 하나에 들어 있는데 Noir가 파일 크기 상한 때문에 건너뛰었고, 초기 리포트는 "이 프로젝트는 아무것도 문서화하지 않았다"고 결론 내렸습니다. 불완전한 게 아니라 그냥 틀렸고, 심지어 확신에 차 있었죠. 지금은 Noir가 스펙 문서에 별도의 크기 예산을 주고([#2671](https://github.com/owasp-noir/noir/pull/2671)), alibi는 Noir가 못 읽었다고 보고한 것을 finding 위에 출력합니다. 관점이 없는 것과 비어 있는 것은 정반대의 의미거든요.

나머지도 같은 결입니다. 다른 관점과 아슬아슬하게 어긋난 엔드포인트(같은 경로에 다른 verb, 한쪽은 파라미터인데 한쪽은 리터럴)의 finding은 강등하고 검토 표시를 답니다. "코드엔 있고 문서엔 없다"와 "둘 다 있는데 alibi가 짝을 못 맞췄다"는 겉보기에 구분이 안 되니까요. 스냅샷에는 어떤 규칙이 실제로 평가됐는지를 기록합니다. 한 번의 실행에서 계약 디렉터리를 빼먹으면 `SHADOW`가 아무것도 평가하지 않는데, 단순 비교에는 그게 모든 shadow API가 닫힌 것과 똑같이 보이기 때문입니다.

이 모든 것 아래에 정규화 규칙 하나가 깔려 있습니다. 경로 파라미터의 이름은 그 정체성의 일부가 아니다. `/users/<int:user_id>`와 `/users/{id}`와 `/users/:id`는 같은 자리를 가리키고, 중요한 건 위치와 `/`를 건너는지 여부뿐입니다. 이 규칙은 믿기 전에 Noir 테스트 트리의 라우트 픽스처 전체, 33개 언어 3,195개 URL에 돌려봤습니다.

## 멈추는 지점

alibi는 Noir가 읽을 수 있는 것만 대조하고, 잘못된 입도로 읽힌 관점은 아예 안 읽힌 관점보다 나쁩니다. Argo CD가 위에서 본 그 천장에 걸려 있고요. authentik은 설치된 앱들의 `urls` 모듈을 런타임에 import해 URLconf를 조립하는데, 정적 분석으로는 따라갈 수 없습니다. flipt는 gRPC 게이트웨이를 마운트해서 Go 소스에 라우트가 정확히 하나입니다. 셋 다 겹침 가드에 걸려 보류되고, 리포트는 finding을 지어내는 대신 이유를 적습니다.

대신 NetBox가 의도한 워크플로를 보여주는 사례입니다. 저장소 하나에 표면이 둘. 서버 렌더링 웹 UI와 DRF REST API가 있고 계약은 후자만 기술합니다. 통째로 스캔하면 746건이 나오는데, 대부분은 "웹 UI는 API 스펙에 없다"는 사실이지만 쓸모없는 관찰입니다. 계약이 다루는 범위로 좁히면:

```console
$ alibi scan ./netbox --ignore '^/(?!api/)'
```

shadow API 세 건이 남습니다(`/api/plugins`, `/api/schema/redoc`, `/api/schema/swagger-ui`). 셋 다 실제로 서비스되고, 셋 다 스키마에는 정말로 없습니다.

만드는 과정에서 Noir 쪽으로도 수정이 흘러갔습니다. 오퍼레이션을 `$ref`로 다른 파일에 분할해 둔 OpenAPI 문서([#2673](https://github.com/owasp-noir/noir/pull/2673)), Django 프로젝트가 실제로 노출하는 DRF 표면([#2672](https://github.com/owasp-noir/noir/pull/2672)), 그리고 위의 스펙 크기 예산. 동반 도구가 스캐너를 스트레스 테스트하는 이 루프가 alibi의 두 번째 역할이 될지도 모르겠습니다.

## 써보기

```bash
uv tool install noir-alibi   # 또는: pipx install noir-alibi
alibi scan ./service ./contracts ./prod.har
```

`PATH`에 noir 1.0.0 이상이 필요합니다. `-f sarif`는 code scanning에 올라가고, `--fail-on high`는 빌드를 막고, 소스 옆의 `.alibi.yml`은 의도된 간극을 억제합니다.

아직 초기입니다. alibi가 사실이 아닌 말을 한다면 그게 정확히 이 도구가 스스로에게서 잡아내려 만든 종류의 버그이니, [이슈로 알려주세요](https://github.com/owasp-noir/alibi/issues). 즐거운 hunting 되세요 :D
