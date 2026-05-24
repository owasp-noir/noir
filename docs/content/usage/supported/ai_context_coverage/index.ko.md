+++
title = "AI 컨텍스트"
description = "guards, callees, sinks, validators, signals를 모아 엔드포인트별로 제공하는 AI 리뷰 컨텍스트입니다."
weight = 5
sort_by = "weight"

+++

Noir는 각 엔드포인트에 구조화된 **AI 리뷰 컨텍스트**를 붙일 수 있습니다. LLM 기반 SAST 도구, 코드 리뷰어, 보안 에이전트가 라우트를 분류할 때 흔히 필요한 정적 신호를 한 번에 모아두는 기능으로, 저장소를 직접 다시 훑지 않아도 되도록 합니다.

활성화하려면 `--ai-context`를 사용하세요:

```bash
noir scan . --ai-context
```

쉼표 구분 bucket 목록을 넘기면 원하는 카테고리만 남깁니다. 필터는 데이터 단에서 동작하므로 JSON / SARIF / YAML / Postman / OAS 모두 동일한 선택을 봅니다 (plain-text 렌더러만이 아니라).

```bash
noir scan . --ai-context=guards,sinks       # auth + 위험 sink 만
noir scan . --ai-context=callee             # 1-hop handler callee 만
noir scan . --ai-context=all                # "전부" 의 명시적 형태
noir scan . --ai-context                    # bare 형태, 동일하게 "전부"
```

유효한 feature 이름: `guards`, `callee`, `sinks`, `validators`, `signals` (그리고 `all`). 대소문자 구분 없음.

plain 출력에서는 비어있지 않은 컨텍스트를 가진 엔드포인트마다 `ai_context:` 블록이 추가됩니다. 모델 기반 출력에서는 다음 위치에 동일한 구조가 노출됩니다.

| 형식 | AI 컨텍스트 위치 |
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
| `callees` | `--include callee`로 수집되는 1-hop 핸들러 callee를 AI 컨텍스트 구조 안에서 다시 노출 |
| `sinks` | 핸들러 본문이나 callee 이름에서 추론된 위험 가능 동작 (SQL, 명령 실행, 역직렬화, 템플릿 렌더링, 파일 I/O, 리다이렉트 등) |
| `validators` | 입력 검증/정제 신호 (스키마 검증기, 파라미터 형 변환, 허용 목록 패턴). sink 위험을 줄여줄 수 있는 단서 |
| `signals` | 그 외 라우트 형태 힌트 (가드 없는 상태 변경 메서드, object-level 인가 점검이 필요한 path-id 사용, 파일 업로드 동작 등) |

리스트는 best-effort입니다. 휴리스틱 신뢰도가 항목별로 노출되므로 소비자 쪽에서 임계값으로 거를 수 있습니다. 출력 크기를 제한하기 위해 버킷당 최대 16개 항목을 유지합니다.

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

- AI 컨텍스트는 **부가적**입니다. 휴리스틱에 걸리지 않는 엔드포인트는 플래그 없이 돌렸을 때와 동일하게 나옵니다 (직렬화된 모델에 `ai_context` 키가 추가되지 않음).
- 휴리스틱은 보수적으로 튜닝되어 있지만 거짓 양성/음성 모두 존재합니다. 항목은 결론이 아닌 priors로 다루세요.
- guard/sink/validator 패턴은 점진적으로 개선됩니다. Noir가 이미 지원하는 프레임워크 매트릭스에 걸쳐 단일 컨텍스트 스키마가 통하도록 의도적으로 cross-language로 설계됐습니다.
- AI 컨텍스트의 많은 부분이 callee 커버리지에서 비롯됩니다. 어떤 프레임워크가 오늘날 핸들러 callee를 노출하는지는 [Callee 커버리지](@/usage/supported/callee_coverage/index.md)를 참고하세요.
