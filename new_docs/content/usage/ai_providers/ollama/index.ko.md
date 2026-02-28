+++
title = "Ollama와 함께 Noir 사용하기"
description = "심층적인 엔드포인트 분석을 위해 Noir를 Ollama와 통합하여 로컬 대규모 언어 모델(LLM)을 실행하는 방법을 알아보세요. 이 가이드는 설정 지침과 예제 명령어를 제공합니다."
weight = 2
sort_by = "weight"

+++

[Ollama](https://ollama.com)는 자신의 컴퓨터에서 로컬로 대규모 언어 모델(LLM)을 실행할 수 있게 해주는 강력한 도구입니다. Noir를 Ollama와 통합하면 외부 서비스로 데이터를 전송하지 않고도 이러한 모델의 분석 기능을 활용하여 코드에 대한 더 깊은 통찰력을 얻을 수 있습니다.

이 설정은 보안에 민감한 환경이나 코드 분석을 위해 다양한 오픈소스 모델을 실험하고 싶은 개발자에게 이상적입니다.

## Ollama 설정

Noir와 함께 Ollama를 사용하기 전에 Ollama를 설치하고 모델과 함께 실행해야 합니다.

1.  **Ollama 설치**: 아직 설치하지 않았다면 [공식 웹사이트](https://ollama.com)에서 Ollama를 다운로드하고 설치하세요.
2.  **모델 다운로드**: 분석에 사용할 모델을 가져와야 합니다. 이 예제에서는 Microsoft의 강력하고 가벼운 모델인 `phi-3`를 사용하겠습니다.

    ```bash
    ollama pull phi-3
    ```

3.  **모델 서빙**: Noir에서 모델을 사용할 수 있도록 하려면 모델을 서빙해야 합니다. 이는 일반적으로 명령을 실행할 때 Ollama에 의해 자동으로 처리되지만, 다음과 같이 실행 중인지 확인할 수 있습니다:

    ```bash
    ollama serve phi-3
    ```

## Ollama와 함께 Noir 실행

Ollama가 설정되고 모델이 서빙되면 `--ai-provider` 플래그를 `ollama`로 설정하여 Noir를 실행할 수 있습니다. 또한 `--ai-model` 플래그로 사용할 모델을 지정해야 합니다.

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=ollama \
     --ai-model=phi-3
```

이 명령을 실행하면 Noir는 표준 분석을 수행한 다음 발견된 엔드포인트를 추가 검사를 위해 로컬 Ollama 서빙 모델로 전송합니다. 모델은 잠재적 보안 취약점을 식별하고, 개선사항을 제안하거나, 엔드포인트 기능에 대한 자연어 요약을 제공할 수 있습니다.

이 통합을 통해 Noir의 강력한 코드 스캐닝 기능과 로컬 LLM의 고급 추론을 결합하여 애플리케이션을 분석하는 포괄적이고 안전한 방법을 제공합니다.