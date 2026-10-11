+++
title = "AI 컨텍스트"
description = "guards, callees, sources, sinks, validators, signals를 모아 엔드포인트별로 제공하는 AI 리뷰 컨텍스트입니다."
weight = 5
sort_by = "weight"

+++

Noir는 각 엔드포인트에 구조화된 **AI 리뷰 컨텍스트**를 붙일 수 있습니다. LLM 기반 SAST 도구, 코드 리뷰어, 보안 에이전트가 라우트를 검토할 때 필요한 정적 신호를 한곳에 모아 주므로, 저장소를 직접 훑지 않아도 됩니다.

`--ai-context`로 켭니다.

```bash
noir scan . --ai-context
```

버킷 이름을 쉼표로 구분해 넘기면 필요한 카테고리만 남습니다. 필터가 데이터 자체에 적용되므로 JSON, SARIF, YAML, Postman, OAS 출력도 plain 출력과 같은 선택을 따릅니다.

```bash
noir scan . --ai-context=guards,sinks       # auth + sink, 연결된 시그널 포함
noir scan . --ai-context=callee             # 1-hop handler callee 만
noir scan . --ai-context=all                # "전부" 의 명시적 형태
noir scan . --ai-context                    # bare 형태, 동일하게 "전부"
```

쓸 수 있는 이름: `guards`, `callee`, `sources`, `sinks`, `validators`, `signals` (그리고 `all`). 대소문자는 구분하지 않습니다.

파생 시그널은 근거 버킷과 연결된 채로 남습니다. `signals`를 선택하면 그
시그널에 필요한 증거(예: `ssrf` → `outbound_http` sink)가 함께 유지되고,
증거 버킷만 선택하면 그에 연결된 시그널만 남습니다(예: `guards,sinks`에도
`authz_absence`가 남음). 여러 버킷을 묶어 판단하는 `priority_review`는
선택에 `signals`가 있을 때만 나옵니다(인자 없는 `--ai-context`와 `all`에는
포함됩니다).

plain 출력에서는 컨텍스트가 있는 엔드포인트마다 `ai_context:` 블록이 붙습니다. 구조화된 포맷에서는 같은 구조가 다음 위치에 들어갑니다.

| 포맷 | AI 컨텍스트 위치 |
|---|---|
| JSON / JSONL / YAML / TOML | `endpoints[].ai_context` |
| OpenAPI 2.0 / 3.0 | 오퍼레이션 단위 `x-noir-ai-context` 확장 |
| SARIF | `result.properties.noir.ai_context` |
| Postman | 아이템 설명에 부착 |
| cURL / HTTPie / only-url / only-param | 의도적으로 생략 (기본 출력 안정성 유지) |

## 무엇이 들어가나

각 버킷은 `kind`, `name`, 선택적인 `source`, `description`, `path`, `line`, `confidence`, `snippet`을 가진 항목 배열입니다. 버킷 종류:

| 버킷 | 의미 |
|---|---|
| `guards` | 라우트에 감지된 인증/인가 게이트 (미들웨어, 데코레이터, `requires_auth`, 역할 체크 등) |
| `callees` | `--include callee`로 모으는 1-hop 핸들러 callee. 한곳에서 볼 수 있도록 AI 컨텍스트 안에도 다시 넣습니다 |
| `sources` | 핸들러에 도달하는 공격자 제어 입력. 요청 파라미터·헤더·쿠키·GraphQL 필드와 모바일 딥링크 페이로드가 여기 들어갑니다. 검토할 만한 서버 측 값 출처(Spring `@Value` 시크릿, WebSocket CORS 정책 등)도 함께 기록됩니다 |
| `sinks` | 핸들러 본문이나 callee 이름에서 추론된 위험 가능 동작 (SQL, 명령 실행, 역직렬화, 템플릿 렌더링, 파일 I/O, 리다이렉트 등) |
| `validators` | 입력 검증/정제 신호 (스키마 검증기, 파라미터 형 변환, 허용 목록 패턴). sink 위험을 줄여줄 수 있는 단서 |
| `signals` | 그 외 라우트 형태 힌트 (가드 없는 상태 변경 메서드, object-level 인가 점검이 필요한 path-id 사용, 파일 업로드 동작 등) |

목록은 최선을 다해 찾은 결과입니다. 항목마다 휴리스틱 신뢰도가 있어서 받는 쪽에서 기준값으로 거를 수 있습니다. 출력이 너무 커지지 않도록 버킷당 최대 16개 항목만 남깁니다.

비어 있지 않은 컨텍스트에는 `"untrusted_fields": ["name", "path", "snippet"]`도 함께 들어갑니다. 이 필드는 스캔한 저장소에서 그대로 가져온 값이라, `snippet`에는 그 코드를 작성한 쪽의 주석과 문자열 리터럴이 포함됩니다. 이 출력을 LLM에 넘길 때는 이 필드를 신뢰할 수 없는 데이터로 다루고 지시문과 분리하세요.

이 구조는 JSON Schema로 [`schemas/ai-context.schema.json`](https://owasp-noir.github.io/noir/schemas/ai-context.schema.json)에 공개되어 있어, 검증기나 안정적인 형식이 필요한 프롬프트에서 그대로 쓸 수 있습니다. 신뢰할 수 없는 필드에는 `"x-noir-untrusted": true`가 붙어 있습니다. 항목의 `kind` 값은 열린 어휘라서 새 값이 추가되어도 스키마는 바뀌지 않습니다.

## 대표 사용 사례

- **AI SAST**: 엔드포인트 인벤토리와 AI 컨텍스트를 LLM에 함께 넘기면, 라우트 구조를 다시 발견하지 않아도 공격 표면에서 도달 가능한 취약점에 집중할 수 있습니다.
- **수동 트리아지**: 대규모 JSON/SARIF 리포트를 sink 종류나 `signals`(예: `state_changing_without_guard`)로 정렬·필터링하기 좋습니다.
- **CI 게이팅**: `sinks` 중 `validators`가 없는 것만 골라 PR에서 위험 엔드포인트를 표시하는 데 활용할 수 있습니다.

## 다른 플래그와 조합

```bash
# 1-hop callee와 AI 컨텍스트 블록을 함께 출력
noir scan . --include callee --ai-context

# LLM 기반 SAST 파이프라인용 JSON 출력
noir scan . --ai-context -f json -o noir-context.json

# 오퍼레이션마다 `x-noir-ai-context`가 붙은 OpenAPI 내보내기
noir scan . --ai-context -f oas3 -o spec.json
```

## 보완 메모

- AI 컨텍스트는 **덧붙이기만** 합니다. 휴리스틱에 걸리지 않는 엔드포인트는 플래그 없이 돌렸을 때와 동일하게 나옵니다 (직렬화된 모델에 `ai_context` 키가 추가되지 않음).
- 휴리스틱은 보수적으로 튜닝되어 있지만 거짓 양성/음성 모두 존재합니다. 항목은 확정된 결론이 아니라 검토를 시작할 단서로 다루세요.
- guard/sink/validator 패턴은 계속 개선됩니다. 하나의 컨텍스트 스키마가 Noir가 지원하는 모든 프레임워크에 통하도록, 패턴은 일부러 언어에 묶이지 않게 설계했습니다.
- AI 컨텍스트의 많은 부분이 callee 커버리지에서 비롯됩니다. 현재 어떤 프레임워크가 핸들러 callee를 내보내는지는 [Callee 커버리지](@/usage/supported/callee_coverage/index.ko.md)를 참고하세요.
