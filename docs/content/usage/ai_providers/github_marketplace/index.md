+++
title = "Using Noir with GitHub Marketplace Models"
description = "Learn how to use AI models from the GitHub Marketplace with Noir. This guide shows you how to authenticate with a Personal Access Token and run Noir to get AI-powered analysis."
weight = 6
sort_by = "weight"

[extra]
+++

Noir can integrate with AI models available through the [GitHub Marketplace](https://github.com/marketplace/models), allowing you to leverage a wide range of powerful language models for your code analysis.

## Setting Up the GitHub Marketplace Integration

To use models from the GitHub Marketplace, you will need a GitHub Personal Access Token (PAT) for authentication.

1.  **Generate a Personal Access Token**: Follow the instructions in the [GitHub documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) to create a PAT. Ensure it has the necessary permissions to access the AI models.
2.  **Choose a Model**: Browse the [GitHub Marketplace](https://github.com/marketplace/models) to find a model that suits your needs.

## Running Noir with GitHub Marketplace Models

Once you have your PAT, you can run Noir with the `--ai-provider` flag set to either `github` or `azure`, depending on the model's hosting. You will also need to provide your PAT with the `--ai-key` flag and specify the model with `--ai-model`.

*   **Using the GitHub API**:

    ```bash
    noir -b ./spec/functional_test/fixtures/hahwul \
         --ai-provider=github \
         --ai-model=gpt-4o \
         --ai-key=github_pat_...
    ```

*   **Using the Azure Inference API**:

    Some GitHub Marketplace models are served through Azure. In this case, you would use the `azure` provider:

    ```bash
    noir -b ./spec/functional_test/fixtures/hahwul \
         --ai-provider=azure \
         --ai-model=gpt-4o \
         --ai-key=github_pat_...
    ```

This integration allows you to easily incorporate a variety of AI models into your development workflow, all managed through your existing GitHub account.

