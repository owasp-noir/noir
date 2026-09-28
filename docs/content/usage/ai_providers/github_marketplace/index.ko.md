+++
title = "GitHub Models 제공업체(종료)"
description = "GitHub Models는 2026년 7월 30일 종료되었습니다. 마이그레이션 안내와 현재 사용할 수 있는 Noir AI 제공업체를 확인하세요."
weight = 6
sort_by = "weight"

+++

GitHub는 2026년 7월 30일 [GitHub Models](https://docs.github.com/en/github-models)를 종료했습니다. 모델 카탈로그, 추론 API, 플레이그라운드, BYOK 기능을 더 이상 사용할 수 없습니다.

이 페이지는 기존 Noir 설정을 옮길 때 참고할 수 있도록 남겨 둔 마이그레이션 안내입니다. 새 스캔에는 `github` 제공업체를 사용하지 마세요.

## 지원되는 제공업체 선택

다음 지원 제공업체 중 하나를 사용하세요.

*   [Azure AI](../azure/): Microsoft Foundry 리소스에 연결합니다.
*   [OpenAI](../openai/): OpenAI API로 OpenAI 모델을 사용합니다.
*   [OpenRouter](../openrouter/): 하나의 API로 여러 모델에 접근합니다.
*   [ACP 에이전트](../acp/): Codex, Gemini, Claude 또는 다른 ACP 호환 에이전트에 연결합니다.

{% alert_warning() %}
Noir의 `github` 제공업체는 기존 설정과의 호환성을 위해 남아 있지만, GitHub Models 서비스 자체는 종료되었습니다. 위 목록에서 지원되는 제공업체를 선택하세요.
{% end %}
