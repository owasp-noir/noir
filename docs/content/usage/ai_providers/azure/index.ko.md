+++
title = "Azure AI와 함께 Noir 사용하기"
description = "GitHub Models를 통해 Azure AI의 언어 모델과 Noir를 연결하는 방법을 알아보세요. API 키를 구성하고 Azure AI와 함께 Noir를 실행하는 방법을 배워보세요."
weight = 2
sort_by = "weight"

+++

Noir를 [Azure AI](https://azure.microsoft.com/ko-kr/products/ai-services)와 통합하면 Microsoft의 Azure 플랫폼에서 호스팅되는 강력한 언어 모델을 활용할 수 있습니다. Azure AI는 GitHub Models 추론 엔드포인트를 통해 다양한 모델에 대한 액세스를 제공하여 코드베이스에 대한 AI 기반 분석을 쉽게 받을 수 있습니다.

## Azure AI 통합 설정

Azure AI와 함께 Noir를 사용하려면 GitHub Models를 통해 Azure AI 서비스에 액세스해야 합니다.

1.  **API 키 획득**: Azure AI 서비스에 가입하고 [Azure AI Inference 포털](https://models.inference.ai.azure.com)에서 API 키를 받으세요.
2.  **모델 선택**: Azure AI를 통해 사용 가능한 적절한 모델을 선택하세요. 모델은 기능과 가격이 다양합니다.

## Azure AI와 함께 Noir 실행

API 키를 확보했다면 `--ai-provider` 플래그를 `azure`로 설정하여 Noir를 실행할 수 있습니다. 또한 `--ai-key` 플래그로 API 키를 제공하고 `--ai-model`로 모델을 지정해야 합니다.

```bash
noir -b ./myapp \
     --ai-provider=azure \
     --ai-model=YOUR_MODEL_NAME \
     --ai-key=YOUR_API_KEY
```

`azure` 제공자 접두사는 자동으로 `https://models.inference.ai.azure.com`의 Azure AI 추론 엔드포인트를 사용합니다.

## 환경 변수 사용

명령줄에서 API 키를 전달하지 않으려면 환경 변수로 설정할 수 있습니다:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir -b ./myapp --ai-provider=azure --ai-model=YOUR_MODEL_NAME
```

이 명령을 실행하면 Noir는 먼저 코드를 스캔하여 엔드포인트를 식별합니다. 그런 다음 이 정보를 Azure AI API로 전송하여 고급 분석을 수행합니다. 여기에는 다음이 포함될 수 있습니다:

*   각 엔드포인트가 수행하는 작업에 대한 **자연어 설명**
*   **잠재적 보안 취약점 식별**
*   **코드 품질 개선 제안** 및 모범 사례 준수

이 통합은 엔터프라이즈급 AI 분석으로 개발 워크플로를 향상시키는 강력한 방법을 제공합니다.
