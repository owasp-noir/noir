+++
title = "OpenAI와 함께 Noir 사용하기"
description = "GPT-4o 같은 OpenAI 모델을 Noir와 연결하여 AI 기반 코드 분석을 수행하는 방법입니다."
weight = 4
sort_by = "weight"

+++

Noir를 [OpenAI](https://openai.com)와 통합하여 GPT-4o 같은 언어 모델로 코드 분석 및 엔드포인트 탐지를 수행할 수 있습니다.

## 설정

1.  **API 키 획득**: [OpenAI 대시보드](https://platform.openai.com/api-keys)에서 API 키를 생성하세요.
2.  **모델 선택**: `gpt-4o` 권장

## 사용 방법

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=openai \
     --ai-model=gpt-4o \
     --ai-key=sk-...
```

OpenAI를 통해 자연어 엔드포인트 설명, 보안 취약점 식별, 코드 품질 개선 제안을 받을 수 있습니다.
