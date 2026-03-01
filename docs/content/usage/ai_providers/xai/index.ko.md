+++
title = "xAI와 함께 Noir 사용하기"
description = "xAI Grok 모델을 Noir와 연결하여 코드 분석을 수행하는 방법입니다."
weight = 5
sort_by = "weight"

+++

[xAI](https://x.ai)의 Grok 모델을 사용하여 코드 분석 및 엔드포인트 탐지를 수행할 수 있습니다.

## 설정

1.  **API 키 획득**: [xAI 웹사이트](https://x.ai/api)에서 API 키를 받으세요.
2.  **모델 선택**: 사용할 모델을 선택하세요 (예: `grok-2-1212`).

## 사용 방법

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=xai \
     --ai-model=grok-2-1212 \
     --ai-key=xai-...
```

xAI를 통해 엔드포인트 분석, 보안 취약점 식별, 코드 개선 제안을 받을 수 있습니다.
