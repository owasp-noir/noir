+++
title = "GitHub Marketplace 모델과 함께 Noir 사용하기"
description = "GitHub Marketplace의 AI 모델을 Noir와 함께 사용하는 방법입니다."
weight = 6
sort_by = "weight"

+++

[GitHub Marketplace](https://github.com/marketplace/models)의 AI 모델을 Noir와 함께 사용할 수 있습니다.

## 설정

1.  **Personal Access Token 생성**: [GitHub 문서](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)에 따라 PAT를 생성하세요. AI 모델 접근 권한이 필요합니다.
2.  **모델 선택**: [GitHub Marketplace](https://github.com/marketplace/models)에서 모델을 선택하세요.

## 사용 방법

**GitHub API 사용**:

```bash
noir scan ./spec/functional_test/fixtures/hahwul \
     --ai-provider=github \
     --ai-model=gpt-5.5 \
     --ai-key=github_pat_...
```

{% alert_warning() %}
과거에는 공유 Azure Inference 엔드포인트(`--ai-provider=azure`)로도 GitHub Models를 사용할 수 있었지만, 해당 엔드포인트는 폐기되어 `models.inference.ai.azure.com`이 더 이상 DNS에서 해석되지 않습니다. 위 예시처럼 `--ai-provider=github`를 사용하세요.
{% end %}
