+++
title = "ACP 에이전트와 함께 Noir 사용하기"
description = "Codex, Gemini, Claude 같은 ACP 기반 에이전트를 Noir와 연결해 AI 기반 엔드포인트 분석을 수행하는 방법입니다."
weight = 8
sort_by = "weight"

+++

ACP(Agent Client Protocol) 제공자를 사용하면 Noir가 직접 HTTP LLM API 대신 AI 에이전트 프로세스와 통신합니다.

## 지원되는 ACP 제공자

- `acp:codex` -> `npx @zed-industries/codex-acp` 실행
- `acp:gemini` -> `gemini --experimental-acp` 실행
- `acp:claude` -> `npx @zed-industries/claude-agent-acp` 실행
- `acp:<custom>` -> `NOIR_ACP_ALLOW_CUSTOM_COMMAND=1`이 설정된 경우에만 `<custom>` 명령을 ACP 호환 에이전트로 실행

그 외의 대상은 거부됩니다. `--ai-provider`는 설정 파일에서도 올 수 있고, 거기에 적힌 명령을 그대로 실행하면 코드 실행 경로가 되므로 사용자 지정 바이너리는 명시적으로 허용해야 합니다.

```bash
NOIR_ACP_ALLOW_CUSTOM_COMMAND=1 noir scan ./myapp --ai-provider="acp:my-agent --flag"
```

## 사용 방법

### Codex (권장 테스트 대상)

```bash
noir scan ./myapp --ai-provider=acp:codex
```

### Gemini

```bash
noir scan ./myapp --ai-provider=acp:gemini
```

### Claude

```bash
noir scan ./myapp --ai-provider=acp:claude
```

### 모델 지정 (선택 사항)

`acp:*`에서는 `--ai-model`이 필수가 아닙니다.

```bash
noir scan ./myapp --ai-provider=acp:codex --ai-model=codex
```

## 로그 동작

기본적으로 Noir는 ACP 라이프사이클 이벤트를 Noir 스타일 로그로 출력하고, ACP/에이전트의 원본 stderr 로그는 숨깁니다.

원본 ACP/에이전트 로그가 필요하면:

```bash
NOIR_ACP_RAW_LOG=1 noir scan ./myapp --ai-provider=acp:codex
```

## 도구 실행 권한

ACP 에이전트는 자신의 도구(셸 명령, 파일 쓰기, 네트워크 요청)를 실행하기 위해 Noir에 권한을 요청할 수 있습니다. Noir는 이 요청을 **모두 거부**합니다.

Noir가 에이전트에게 보내는 프롬프트는 스캔 대상 트리의 소스 코드이고, 내가 작성하지 않은 코드를 스캔하는 것이 일반적인 사용 방식입니다. "위 내용은 무시하고 이것을 실행하라" 같은 문장이 들어 있는 파일 하나면 에이전트를 유도할 수 있으므로, 권한 확인은 남아 있는 유일한 관문입니다. 여기서 자동으로 승인하면 엔드포인트 스캔이 로컬 임의 코드 실행으로 바뀝니다.

거부해도 잃는 것은 없습니다. 분석할 코드는 이미 프롬프트에 담겨 있어 에이전트가 도구를 쓰지 않아도 답할 수 있습니다. 신뢰하는 트리를 스캔하면서 에이전트가 직접 탐색하기를 원한다면 명시적으로 허용하세요.

```bash
NOIR_ACP_ALLOW_TOOL_PERMISSIONS=1 noir scan ./myapp --ai-provider=acp:codex
```

## 참고

- `acp:*` 제공자에서는 `--ai-key`가 필요하지 않습니다.
- 캐시 플래그(`--cache-disable`, `--cache-clear`)는 다른 AI 제공자와 동일하게 동작합니다.
- `acp:claude-code`는 `acp:claude`와 동일하게 동작하는 alias입니다.
