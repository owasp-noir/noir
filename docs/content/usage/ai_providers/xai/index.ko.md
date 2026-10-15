+++
title = "xAI와 함께 Noir 사용하기"
description = "xAI Grok 모델을 Noir에 연결해 코드를 분석하는 방법입니다."
weight = 5
sort_by = "weight"

+++

[xAI](https://x.ai)의 Grok 모델로 코드를 분석하고 엔드포인트를 찾을 수 있습니다.

## 설정

1.  **API 키 발급**: [xAI 웹사이트](https://x.ai/api)에서 API 키를 받으세요.
2.  **모델 선택**: 사용할 모델을 고르세요(예: `grok-4.5`).

## 사용 방법

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=xai \
     --ai-model=grok-4.5 \
     --ai-key=xai-...
```
