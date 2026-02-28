+++
title = "Ollama와 함께 Noir 사용하기"
description = "Noir를 Ollama와 통합하여 로컬 LLM으로 코드 분석을 수행하는 방법입니다."
weight = 2
sort_by = "weight"

+++

[Ollama](https://ollama.com)를 사용하면 외부 서비스로 데이터를 전송하지 않고 로컬에서 대규모 언어 모델을 실행하여 코드를 분석할 수 있습니다.

## 설정

1.  **Ollama 설치**: [공식 웹사이트](https://ollama.com)에서 다운로드하세요.
2.  **모델 다운로드**: 분석에 사용할 모델을 가져오세요 (예: `phi-3`).

    ```bash
    ollama pull phi-3
    ```

3.  **모델 서빙**:

    ```bash
    ollama serve phi-3
    ```

## 사용 방법

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=phi-3
```

Ollama를 통해 취약점 탐지, 코드 개선 제안, 엔드포인트 기능 설명 등 로컬 AI 분석을 수행할 수 있습니다.
