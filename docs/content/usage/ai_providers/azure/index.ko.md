+++
title = "Azure AI와 함께 Noir 사용하기"
description = "Azure AI 언어 모델을 Noir와 연결하여 코드 분석을 수행하는 방법입니다."
weight = 2
sort_by = "weight"

+++

[Azure AI](https://azure.microsoft.com/ko-kr/products/ai-services) 언어 모델을 GitHub Models 추론 엔드포인트를 통해 사용할 수 있습니다.

## 설정

1.  **API 키 획득**: [Azure AI Inference 포털](https://models.inference.ai.azure.com)에서 API 키를 받으세요.
2.  **모델 선택**: Azure AI에서 사용 가능한 모델을 선택하세요.

## 사용 방법

```bash
noir -b ./myapp \
     --ai-provider=azure \
     --ai-model=YOUR_MODEL_NAME \
     --ai-key=YOUR_API_KEY
```

`azure` 제공자는 `https://models.inference.ai.azure.com` 엔드포인트를 사용합니다.

환경 변수 사용:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir -b ./myapp --ai-provider=azure --ai-model=YOUR_MODEL_NAME
```

Azure AI를 통해 자연어 엔드포인트 설명, 보안 취약점 식별, 코드 품질 개선 제안을 받을 수 있습니다.
