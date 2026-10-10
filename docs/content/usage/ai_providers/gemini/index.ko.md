+++
title = "Google Gemini와 함께 Noir 사용하기"
description = "Google의 OpenAI 호환 엔드포인트로 Gemini 모델을 Noir와 연결하는 방법입니다."
weight = 5
sort_by = "weight"

+++

`gemini` 프리셋은 Google의 [OpenAI 호환 Gemini 엔드포인트](https://ai.google.dev/gemini-api/docs/openai)를 가리킵니다. 이 엔드포인트는 Noir가 `response_format`으로 보내는 JSON 스키마를 지원합니다.

## 설정

1.  **API 키**: [Google AI Studio](https://aistudio.google.com/apikey)에서 발급하세요.
2.  **모델**: `gemini-3.1-pro`나 `gemini-3.5-flash` 같은 모델 ID를 고르세요.

## 사용 방법

```bash
noir scan ./myapp \
     --ai-provider=gemini \
     --ai-model=gemini-3.1-pro \
     --ai-key=AIza...
```

환경 변수 사용:

```bash
export NOIR_AI_KEY=AIza...
noir scan ./myapp --ai-provider=gemini --ai-model=gemini-3.5-flash
```
