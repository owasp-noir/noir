---
title: Github
parent: AI Integration
nav_order: 6
layout: page
---

# Github

## Setup Github marketplace

1. Obtain an API Key: Follow the instructions on Github to obtain a Personal Access Token (PAS)[^1].
2. Select and Configure the Model: Choose the desired model from the [Github marketplace](https://github.com/marketplace/models)[^2] and ensure it is properly configured.

## Run Noir with Github marketplace Models
To leverage Github marketplace's models capabilities for additional analysis, use the following command:

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=github \
     --ai-model=gpt-4o \
     --ai-key=github_....
```
*Use to models.github.ai*

or 

```bash
noir -b ./spec/functional_test/fixtures/hahwul \
     --ai-provider=azure \
     --ai-model=gpt-4o \
     --ai-key=github_....
```
*Use to models.inference.ai.azure.com*

This command performs the standard Noir operations while utilizing the specified Github or Azure's inference API for enhanced analysis.

[^1]: [https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
[^2]: Github > Marketplace > Models