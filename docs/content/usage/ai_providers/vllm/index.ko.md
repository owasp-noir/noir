+++
title = "vLLM과 함께 Noir 사용하기"
description = "vLLM의 고성능 로컬 LLM 추론을 Noir에 연결하는 방법입니다."
weight = 3
sort_by = "weight"

+++

[vLLM](https://docs.vllm.ai)으로 모델을 로컬에서 서빙하고 Noir가 그 서버를 쓰게 합니다.

## 설정

1.  **vLLM 설치**: [공식 설치 가이드](https://docs.vllm.ai)를 참고하세요.
2.  **모델 서빙**:

    ```bash
    vllm serve google/gemma-4-31B-it
    ```

    8000번 포트에서 OpenAI 호환 서버가 시작됩니다.

## 사용 방법

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=google/gemma-4-31B-it
```

`vllm` 프리셋은 `http://localhost:8000/v1`을 가리킵니다. 다른 호스트나 포트라면 `--ai-provider=http://gpu-box:8000/v1`처럼 URL을 직접 넘기세요.
