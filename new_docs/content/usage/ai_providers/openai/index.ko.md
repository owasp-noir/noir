+++
title = "OpenAI와 함께 Noir 사용하기"
description = "GPT-4o와 같은 OpenAI의 강력한 언어 모델과 Noir를 연결하여 코드의 고급 분석을 받는 방법을 알아보세요. API 키를 구성하고 OpenAI와 함께 Noir를 실행하는 방법을 배워보세요."
weight = 4
sort_by = "weight"

+++

Noir를 [OpenAI](https://openai.com)와 통합하면 GPT-4o와 같은 최첨단 언어 모델의 힘을 활용하여 코드베이스를 분석할 수 있습니다. 이 조합을 통해 단순한 엔드포인트 탐지를 넘어 애플리케이션의 동작, 잠재적 보안 위험 및 전반적인 품질에 대한 정교한 통찰력을 얻을 수 있습니다.

## OpenAI 통합 설정

OpenAI와 함께 Noir를 사용하려면 API 키가 필요합니다.

1.  **API 키 획득**: 아직 계정이 없다면 OpenAI 계정에 가입하고 [대시보드](https://platform.openai.com/api-keys)에서 API 키를 생성하세요.
2.  **모델 선택**: 사용할 OpenAI 모델을 결정하세요. 최상의 결과를 위해 `gpt-4o`와 같은 강력하고 최신 모델을 추천합니다.

## OpenAI와 함께 Noir 실행

API 키를 확보했다면 `--ai-provider` 플래그를 `openai`로 설정하여 Noir를 실행할 수 있습니다. 또한 `--ai-key` 플래그로 API 키를 제공하고 `--ai-model`로 모델을 지정해야 합니다.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-4o \
     --ai-key=sk-...
```

이 명령을 실행하면 Noir는 먼저 코드를 스캔하여 엔드포인트를 식별합니다. 그런 다음 이 정보를 OpenAI API로 전송하고, API가 코드를 분석하여 추가적인 통찰력을 제공합니다. 여기에는 다음이 포함될 수 있습니다:

*   각 엔드포인트가 수행하는 작업에 대한 **자연어 설명**
*   **잠재적 보안 취약점 식별**
*   **코드 품질 개선 제안** 및 모범 사례 준수

이 통합은 명령줄을 떠나지 않고도 세계적 수준의 AI 분석에 액세스할 수 있게 해주는 개발 워크플로를 강화하는 강력한 방법입니다.