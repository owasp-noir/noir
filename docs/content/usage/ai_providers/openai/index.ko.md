+++
title = "OpenAI와 함께 Noir 사용하기"
description = "GPT-5.5 같은 OpenAI 모델을 Noir에 연결해 AI로 코드를 분석하는 방법입니다."
weight = 4
sort_by = "weight"

+++

[OpenAI](https://openai.com)의 GPT-5.5 같은 모델로 코드를 분석하고 엔드포인트를 찾습니다.

## 설정

1.  **API 키 발급**: [OpenAI 대시보드](https://platform.openai.com/api-keys)에서 API 키를 생성하세요.
2.  **모델 선택**: `gpt-5.5` 권장

## 사용 방법

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-5.5 \
     --ai-key=sk-...
```
