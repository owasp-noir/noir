+++
title = "Azure AI와 함께 Noir 사용하기"
description = "Azure AI 언어 모델을 Noir와 연결하여 코드 분석을 수행하는 방법입니다."
weight = 2
sort_by = "weight"

+++

[Microsoft Foundry](https://azure.microsoft.com/ko-kr/products/ai-foundry)(구 Azure AI Foundry)의 언어 모델로 코드 분석을 수행할 수 있습니다.

## 설정

1.  **API 키 획득**: [Microsoft Foundry 포털](https://ai.azure.com)에서 리소스와 키를 만드세요.
2.  **모델 선택**: 모델을 배포하고 배포 이름을 확인하세요.

## 사용 방법

`--ai-provider` 에 사용 중인 Foundry 리소스의 엔드포인트를 직접 지정합니다.

```bash
noir scan ./myapp \
     --ai-provider=https://YOUR-RESOURCE.services.ai.azure.com/models \
     --ai-model=YOUR_DEPLOYMENT_NAME \
     --ai-key=YOUR_API_KEY
```

`--ai-provider` 는 OpenAI 호환 URL을 그대로 받으므로 별도의 프리픽스가 필요 없습니다.

키를 환경 변수로 전달하는 경우:

```bash
export NOIR_AI_KEY=YOUR_API_KEY
noir scan ./myapp \
     --ai-provider=https://YOUR-RESOURCE.services.ai.azure.com/models \
     --ai-model=YOUR_DEPLOYMENT_NAME
```

## `azure` 프리픽스

Noir에는 `https://models.inference.ai.azure.com` 으로 확장되는 `azure` 제공자 프리픽스가 있습니다.

{% alert_warning() %}
이 공용 엔드포인트는 종료되었습니다. `models.inference.ai.azure.com` 은 더 이상 DNS에서 해석되지 않으므로 `--ai-provider=azure` 형태로는 접속할 수 없습니다. 현재 Foundry는 리소스마다 별도의 엔드포인트를 제공하므로, 위의 전체 URL 형태를 사용하세요.
{% end %}
