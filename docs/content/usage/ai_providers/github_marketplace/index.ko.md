+++
title = "GitHub Marketplace 모델과 함께 Noir 사용하기"
description = "GitHub Marketplace의 AI 모델을 Noir와 함께 사용하는 방법을 알아보세요. 이 가이드는 Personal Access Token으로 인증하고 AI 기반 분석을 받기 위해 Noir를 실행하는 방법을 보여줍니다."
weight = 6
sort_by = "weight"

[extra]
+++

Noir는 [GitHub Marketplace](https://github.com/marketplace/models)를 통해 제공되는 AI 모델과 통합되어 코드 분석을 위해 다양한 강력한 언어 모델을 활용할 수 있습니다.

## GitHub Marketplace 통합 설정

GitHub Marketplace의 모델을 사용하려면 인증을 위한 GitHub Personal Access Token(PAT)이 필요합니다.

1.  **Personal Access Token 생성**: [GitHub 문서](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)의 지시사항에 따라 PAT를 생성하세요. AI 모델에 액세스할 수 있는 필요한 권한이 있는지 확인하세요.
2.  **모델 선택**: [GitHub Marketplace](https://github.com/marketplace/models)를 둘러보고 필요에 맞는 모델을 찾으세요.

## GitHub Marketplace 모델과 함께 Noir 실행

PAT를 확보했다면 모델의 호스팅에 따라 `--ai-provider` 플래그를 `github` 또는 `azure`로 설정하여 Noir를 실행할 수 있습니다. 또한 `--ai-key` 플래그로 PAT를 제공하고 `--ai-model`로 모델을 지정해야 합니다.

*   **GitHub API 사용**:

    ```bash
    noir -b ./spec/functional_test/fixtures/hahwul \
         --ai-provider=github \
         --ai-model=gpt-4o \
         --ai-key=github_pat_...
    ```

*   **Azure Inference API 사용**:

    일부 GitHub Marketplace 모델은 Azure를 통해 제공됩니다. 이 경우 `azure` 제공자를 사용합니다:

    ```bash
    noir -b ./spec/functional_test/fixtures/hahwul \
         --ai-provider=azure \
         --ai-model=gpt-4o \
         --ai-key=github_pat_...
    ```

이 통합을 통해 기존 GitHub 계정을 통해 관리되는 다양한 AI 모델을 개발 워크플로에 쉽게 통합할 수 있습니다.