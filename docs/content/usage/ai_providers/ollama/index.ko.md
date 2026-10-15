+++
title = "Ollama와 함께 Noir 사용하기"
description = "Noir를 Ollama와 통합하여 로컬 LLM으로 코드 분석을 수행하는 방법입니다."
weight = 2
sort_by = "weight"

+++

[Ollama](https://ollama.com)를 사용하면 외부 서비스로 데이터를 전송하지 않고 로컬에서 대규모 언어 모델을 실행하여 코드를 분석할 수 있습니다.

## 설정

1.  **Ollama 설치**: [공식 웹사이트](https://ollama.com)에서 다운로드하세요.
2.  **모델 다운로드**: 분석에 사용할 모델을 가져오세요 (예: `gemma4`).

    ```bash
    ollama pull gemma4
    ```

3.  **서버 시작**:

    ```bash
    ollama serve
    ```

## 사용 방법

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=gemma4
```

## 참고

- `ollama` 프리셋은 OpenAI 호환 `/v1` 경로가 아니라 Ollama 네이티브 `/api/generate` API를 사용합니다. Noir는 요청 크기를 잡을 때 쓴 프롬프트 예산에 맞춰 `num_ctx`를 설정하므로, 긴 프롬프트가 Ollama의 작은 기본 컨텍스트에 맞춰 잘리지 않습니다.
- 호스팅된 Ollama나 인증 프록시를 쓴다면 `--ai-key`나 `NOIR_AI_KEY`로 bearer 토큰을 넘길 수 있습니다.
- `--ai-stream`은 이 제공업체에는 적용되지 않습니다.
- 직접 URL을 넘길 때는 호스트 이름에 `ollama`가 들어 있어야 네이티브 API를 씁니다(예: `http://ollama.internal:11434`). `http://gpu-box:11434` 같은 다른 호스트는 OpenAI 호환 클라이언트로 처리되므로 `--ai-provider=http://gpu-box:11434/v1`처럼 경로까지 넣으세요.

> **v0 → v1 마이그레이션:** 독립적인 `--ollama` / `--ollama-model` 플래그는
> v1.0에서 제거되었습니다. 위 예시처럼 통합된 `--ai-provider ollama
> --ai-model NAME` 형태를 사용하세요.
