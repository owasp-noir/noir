+++
title = "vLLM과 함께 Noir 사용하기"
description = "고성능 로컬 LLM 추론을 위해 Noir를 vLLM과 통합하는 방법을 설명하는 가이드입니다. vLLM을 설정하고 이를 Noir와 함께 사용하여 코드 분석을 가속화하는 방법을 알아보세요."
weight = 3
sort_by = "weight"

[extra]
+++

[vLLM](https://docs.vllm.ai)은 대규모 언어 모델(LLM)을 위한 고처리량 및 메모리 효율적인 추론 엔진입니다. vLLM을 Noir와 함께 사용하면 특히 크거나 복잡한 모델로 작업할 때 코드베이스 분석을 크게 가속화할 수 있습니다. 이 통합은 빠르고 로컬이며 비공개 코드 분석이 필요한 개발자에게 완벽합니다.

## vLLM 설정

시작하려면 vLLM을 설치하고 모델을 서빙해야 합니다.

1.  **vLLM 설치**: [공식 vLLM 웹사이트](https://docs.vllm.ai)의 설치 지침에 따라 필수 소프트웨어를 설정하세요.
2.  **모델 서빙**: vLLM이 설치되면 호환되는 모든 모델을 서빙할 수 있습니다. 이 예제에서는 Microsoft의 `phi-3` 모델을 사용하겠습니다.

    ```bash
    vllm serve microsoft/phi-3
    ```

    이 명령은 모델에 대해 OpenAI 호환 API 엔드포인트를 제공하는 로컬 서버를 시작합니다.

## vLLM과 함께 Noir 실행

vLLM에 의해 모델이 서빙되고 있으면 이제 Noir를 실행하고 로컬 LLM을 가리킬 수 있습니다. `--ai-provider` 플래그를 `vllm`과 함께 사용하고 `--ai-model` 플래그로 서빙하고 있는 모델을 지정하세요.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=vllm \
     --ai-model=microsoft/phi-3
```

이 명령을 실행하면 Noir는 초기 코드 스캔을 수행한 다음 발견된 엔드포인트를 vLLM 기반 API로 전송합니다. vLLM이 성능에 고도로 최적화되어 있기 때문에 다른 로컬 추론 솔루션보다 AI 기반 분석이 훨씬 빠를 것으로 예상할 수 있습니다.

이 강력한 조합을 통해 자신의 컴퓨터에서 바로 빠르고 비공개이며 효율적인 코드 분석 파이프라인을 구축할 수 있습니다.