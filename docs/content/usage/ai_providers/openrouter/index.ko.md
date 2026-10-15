+++
title = "OpenRouter와 함께 Noir 사용하기"
description = "OpenRouter의 통합 API로 여러 AI 모델을 Noir에서 쓰는 방법입니다."
weight = 7
sort_by = "weight"

+++

[OpenRouter](https://openrouter.ai)를 쓰면 API 하나로 여러 AI 모델(OpenAI, Anthropic, Google, Meta 등)을 쓸 수 있습니다.

## 설정

1.  **API 키 발급**: [OpenRouter 대시보드](https://openrouter.ai/keys)에서 발급하세요.
2.  **모델 선택**: [OpenRouter Models](https://openrouter.ai/models)에서 쓸 수 있는 모델을 둘러보세요.

## 사용 방법

```bash
noir scan ./myapp \
     --ai-provider=openrouter \
     --ai-model=anthropic/claude-opus-4-8 \
     --ai-key=sk-or-...
```

환경 변수 사용:

```bash
export NOIR_AI_KEY=sk-or-...
noir scan ./myapp --ai-provider=openrouter --ai-model=openai/gpt-5.5
```
