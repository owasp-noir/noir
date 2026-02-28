+++
title = "OpenRouter와 함께 Noir 사용하기"
description = "통합 API를 통해 여러 AI 모델에 액세스하기 위해 OpenRouter를 Noir와 함께 사용하는 방법을 알아보세요. 이 가이드는 OpenRouter API 키를 설정하고 다양한 모델로 Noir를 실행하는 방법을 다룹니다."
weight = 7
sort_by = "weight"

+++

[OpenRouter](https://openrouter.ai)를 사용하면 단일 통합 API를 통해 여러 AI 모델(OpenAI, Anthropic, Google, Meta 등)에 액세스할 수 있습니다. 이 통합을 통해 다양한 제공업체의 모델을 쉽게 전환하고 코드 분석에 가장 적합한 모델을 선택할 수 있습니다.

## OpenRouter 통합 설정

OpenRouter와 함께 Noir를 사용하려면 API 키가 필요합니다.

1.  **API 키 획득**: [OpenRouter 대시보드](https://openrouter.ai/keys)에서 API 키를 생성하세요.
2.  **모델 선택**: [OpenRouter Models](https://openrouter.ai/models)에서 사용 가능한 모델을 둘러보고 필요에 맞는 모델을 선택하세요.

## OpenRouter와 함께 Noir 실행

API 키를 확보했다면 `--ai-provider` 플래그를 `openrouter`로 설정하여 Noir를 실행할 수 있습니다. 또한 `--ai-key` 플래그로 API 키를 제공하고 `--ai-model`로 모델을 지정해야 합니다.

```bash
noir -b ./myapp \
     --ai-provider=openrouter \
     --ai-model=anthropic/claude-3.5-sonnet \
     --ai-key=sk-or-...
```

## 환경 변수 사용

명령줄에서 API 키를 전달하지 않으려면 환경 변수로 설정할 수 있습니다:

```bash
export NOIR_AI_KEY=sk-or-...
noir -b ./myapp --ai-provider=openrouter --ai-model=openai/gpt-4o
```

이 명령을 실행하면 Noir는 먼저 코드를 스캔하여 엔드포인트를 식별합니다. 그런 다음 이 정보를 OpenRouter API로 전송하여 고급 분석을 수행합니다. OpenRouter는 다음과 같은 이점을 제공합니다:

*   여러 제공업체의 100개 이상의 모델에 대한 **액세스**
*   모든 모델을 위한 **통합 API**
*   **자동 폴백 및 로드 밸런싱**
*   **비용 효율적인 모델 선택**

이 통합은 다양한 AI 모델을 쉽게 전환하며 개발 워크플로를 향상시키는 유연한 방법을 제공합니다.
