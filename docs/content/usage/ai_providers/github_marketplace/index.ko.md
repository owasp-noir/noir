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
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=github \
     --ai-model=gpt-4o \
     --ai-key=github_pat_...
```

**Azure Inference API 사용** (Azure를 통해 제공되는 모델):

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=azure \
     --ai-model=gpt-4o \
     --ai-key=github_pat_...
```
