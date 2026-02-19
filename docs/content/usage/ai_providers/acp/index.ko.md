+++
title = "ACP 에이전트와 함께 Noir 사용하기"
description = "Codex, Gemini 같은 ACP 기반 에이전트를 Noir와 연결해 AI 기반 엔드포인트 분석을 수행하는 방법입니다."
weight = 8
sort_by = "weight"

[extra]
+++

ACP(Agent Client Protocol) 제공자를 사용하면 Noir가 직접 HTTP LLM API 대신 AI 에이전트 프로세스와 통신합니다.

## 지원되는 ACP 제공자

- `acp:codex` -> `npx @zed-industries/codex-acp` 실행
- `acp:gemini` -> `gemini --experimental-acp` 실행
- `acp:<custom>` -> `<custom>` 명령을 ACP 호환 에이전트로 실행

## 사용 방법

### Codex (권장 테스트 대상)

```bash
noir -b ./myapp --ai-provider=acp:codex
```

### Gemini

```bash
noir -b ./myapp --ai-provider=acp:gemini
```

### 모델 지정 (선택 사항)

`acp:*`에서는 `--ai-model`이 필수가 아닙니다.

```bash
noir -b ./myapp --ai-provider=acp:codex --ai-model=codex
```

## 로그 동작

기본적으로 Noir는 ACP 라이프사이클 이벤트를 Noir 스타일 로그로 출력하고, ACP/에이전트의 원본 stderr 로그는 숨깁니다.

원본 ACP/에이전트 로그가 필요하면:

```bash
NOIR_ACP_RAW_LOG=1 noir -b ./myapp --ai-provider=acp:codex
```

## 참고

- `acp:*` 제공자에서는 `--ai-key`가 필요하지 않습니다.
- 캐시 플래그(`--cache-disable`, `--cache-clear`)는 다른 AI 제공자와 동일하게 동작합니다.
