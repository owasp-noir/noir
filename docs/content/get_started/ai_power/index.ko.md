+++
title = "AI 기반 분석"
description = "코드의 고급 분석을 위해 Noir의 AI 통합을 사용하는 방법을 알아보세요. 이 가이드는 OpenAI, xAI 및 로컬 모델과 같은 LLM 제공업체에 연결하는 데 필요한 플래그와 옵션을 다룹니다."
weight = 4
sort_by = "weight"

[extra]
+++

Noir는 클라우드 기반 서비스와 로컬 인스턴스 모두의 대규모 언어 모델(LLM)에 연결하여 코드베이스에 대한 더 깊은 수준의 분석을 제공할 수 있습니다. AI를 활용함으로써 Noir는 종종 기본적으로 지원하지 않는 언어와 프레임워크에서 엔드포인트를 식별할 수 있으며, 애플리케이션의 기능에 대한 추가적인 인사이트를 제공할 수 있습니다.

![](./ai_integration.jpeg)

## AI 통합 사용 방법

AI 기반 분석을 활성화하려면 AI 제공업체, 모델 및 API 키를 지정해야 합니다.

```bash
noir -b . --ai-provider <PROVIDER> --ai-model <MODEL_NAME> --ai-key <YOUR_API_KEY>
```

### 명령줄 플래그

*   `--ai-provider`: 사용하려는 AI 제공업체입니다. 이는 사전 설정 접두사(`openai` 또는 `ollama`와 같은) 또는 사용자 정의 API 엔드포인트의 전체 URL일 수 있습니다.
*   `--ai-model`: 분석에 사용하려는 모델의 이름입니다(예: `gpt-4o`).
*   `--ai-key`: AI 제공업체를 위한 API 키입니다. `NOIR_AI_KEY` 환경 변수를 사용하여 설정할 수도 있습니다.
*   `--ai-max-token`: (선택사항) AI 요청에 사용할 최대 토큰 수입니다. 이는 생성된 텍스트의 길이에 영향을 줄 수 있습니다.
*   `--cache-disable`: 현재 실행에서 LLM 디스크 캐시를 비활성화합니다.
*   `--cache-clear`: 실행 전에 LLM 캐시 디렉터리를 비웁니다.

기본적으로 Noir는 AI 응답을 디스크에 캐시하여 반복 분석 속도를 높이고 비용을 줄입니다. 필요 시 위 캐시 플래그를 사용해 캐시를 비활성화하거나 사전 정리할 수 있습니다.

### 지원되는 AI 제공업체

Noir는 다음 AI 제공업체를 지원합니다:

#### OpenAI

```bash
noir -b . --ai-provider openai --ai-model gpt-4o --ai-key YOUR_OPENAI_API_KEY
```

#### xAI (Grok)

```bash
noir -b . --ai-provider xai --ai-model grok-beta --ai-key YOUR_XAI_API_KEY
```

#### Ollama (로컬)

로컬에서 Ollama를 실행하는 경우:

```bash
noir -b . --ai-provider ollama --ai-model llama3.2 --ai-key ""
```

#### vLLM

```bash
noir -b . --ai-provider vllm --ai-model microsoft/DialoGPT-medium --ai-key ""
```

#### LM Studio

로컬 LM Studio 인스턴스의 경우:

```bash
noir -b . --ai-provider lmstudio --ai-model local-model --ai-key lm-studio
```

## AI 분석의 이점

AI 통합을 사용할 때 다음과 같은 이점을 얻을 수 있습니다:

*   **확장된 언어 지원**: Noir가 기본적으로 지원하지 않는 언어와 프레임워크에서 엔드포인트 발견
*   **향상된 정확도**: AI가 복잡한 코드 패턴과 동적 엔드포인트를 식별하는 데 도움
*   **컨텍스트 이해**: AI가 코드의 맥락을 더 잘 이해하여 더 정확한 분석 제공

## 모범 사례

*   적절한 토큰 제한을 설정하여 비용과 성능의 균형을 맞추세요
*   민감한 코드의 경우 로컬 AI 모델 사용을 고려하세요
*   AI 분석 결과를 정적 분석 결과와 함께 검토하여 포괄적인 보안 평가를 수행하세요