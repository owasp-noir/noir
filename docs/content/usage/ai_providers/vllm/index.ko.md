+++
title = "vLLM과 함께 Noir 사용하기"
description = "Noir를 vLLM과 통합하여 고성능 로컬 LLM 추론을 수행하는 방법입니다."
weight = 3
sort_by = "weight"

+++

[vLLM](https://docs.vllm.ai)은 고처리량 LLM 추론 엔진입니다. Noir와 함께 사용하면 빠른 로컬 코드 분석이 가능합니다.

## 설정

1.  **vLLM 설치**: [공식 설치 가이드](https://docs.vllm.ai)를 참고하세요.
2.  **모델 서빙**:

    ```bash
    vllm serve microsoft/phi-3
    ```

    OpenAI 호환 API 엔드포인트를 제공하는 로컬 서버가 시작됩니다.

## 사용 방법

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=microsoft/phi-3
```
