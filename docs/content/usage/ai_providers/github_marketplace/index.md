+++
title = "Using Noir with GitHub Marketplace Models"
description = "Use AI models from GitHub Marketplace with Noir for code analysis."
weight = 6
sort_by = "weight"

+++

Use AI models from the [GitHub Marketplace](https://github.com/marketplace/models) with Noir for code analysis.

## Setup

1.  **Generate a Personal Access Token**: Create a PAT following the [GitHub documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens). Ensure it has permissions to access AI models.
2.  **Choose a Model**: Browse the [GitHub Marketplace](https://github.com/marketplace/models) for available models.

## Usage

**Using the GitHub API**:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=github \
     --ai-model=gpt-4o \
     --ai-key=github_pat_...
```

**Using the Azure Inference API** (for models served through Azure):

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=azure \
     --ai-model=gpt-4o \
     --ai-key=github_pat_...
```
