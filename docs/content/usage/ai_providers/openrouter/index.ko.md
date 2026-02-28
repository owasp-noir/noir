+++
title = "OpenRouter와 함께 Noir 사용하기"
description = "OpenRouter를 통해 여러 AI 모델에 접근하여 Noir와 함께 사용하는 방법입니다."
weight = 7
sort_by = "weight"

+++

[OpenRouter](https://openrouter.ai)를 사용하면 단일 API로 여러 AI 모델(OpenAI, Anthropic, Google, Meta 등)에 접근할 수 있습니다.

## 설정

1.  **API 키 획득**: [OpenRouter 대시보드](https://openrouter.ai/keys)에서 API 키를 생성하세요.
2.  **모델 선택**: [OpenRouter Models](https://openrouter.ai/models)에서 모델을 선택하세요.

## 사용 방법

```bash
noir -b ./myapp \
     --ai-provider=openrouter \
     --ai-model=anthropic/claude-3.5-sonnet \
     --ai-key=sk-or-...
```

환경 변수 사용:

```bash
export NOIR_AI_KEY=sk-or-...
noir -b ./myapp --ai-provider=openrouter --ai-model=openai/gpt-4o
```

OpenRouter의 주요 이점:
*   여러 제공업체의 100개 이상 모델 지원
*   모든 모델을 위한 통합 API
*   자동 폴백 및 로드 밸런싱
*   비용 효율적인 모델 선택
