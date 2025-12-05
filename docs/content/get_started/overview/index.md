+++
title = "Overview"
description = "Learn what OWASP Noir is, how it works, and what its goals are. This page provides a high-level introduction to the project and its key features."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir is a hybrid static and AI-driven analyzer that detects every endpoint in your codebase—from shadow APIs to standard routes. By combining static code analysis with Large Language Model (LLM) capabilities, Noir uncovers hidden endpoints, shadow APIs, and other security blind spots that traditional tools often miss.

## Key Capabilities

- **Attack Surface Discovery**: Analyzes source code to identify your application's complete attack surface, including hidden endpoints, shadow APIs, and other security weaknesses.
- **AI-Powered Analysis**: Leverages LLMs to detect endpoints in any language or framework—even those not natively supported—ensuring comprehensive coverage.
- **SAST-to-DAST Bridge**: Acts as a bridge between static code analysis and dynamic testing by providing discovered endpoints to DAST tools, enabling more accurate and comprehensive security scans.
- **DevSecOps Ready**: Designed for seamless integration into CI/CD pipelines with support for popular security tools like ZAP, Burp Suite, and Caido.
- **Multi-Format Output**: Delivers results in JSON, YAML, OpenAPI Specification, and other formats for easy integration with your existing workflow.

[GitHub](https://github.com/owasp-noir/noir) | [OWASP Project Page](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## How It Works

Noir is built with the [Crystal](https://crystal-lang.org) programming language and is composed of several key components that work together to analyze code:

*   **Detectors**: Identify the technologies used in a codebase.
*   **Analyzers**: Parse the code to find endpoints, parameters, and other interesting information.
*   **LLM Analyzer**: Uses AI to discover endpoints in unsupported or unfamiliar frameworks.
*   **Passive Scanner & Tagger**: Use rules to identify potential vulnerabilities and add contextual tags to the findings.
*   **Deliver**: Send the results to other tools for further analysis.
*   **Output Builder**: Generate reports in various formats.

{% mermaid() %}
flowchart LR
    SourceCode:::highlight --> Detectors

    subgraph Detectors
        direction LR
        Detector1 & Detector2 & Detector3 --> |Condition| PassiveScan
    end

    PassiveScan --> |Results| BaseOptimizer

    Detectors --> |Techs| Analyzers

    subgraph Analyzers
        direction LR
        CodeAnalyzers & FileAnalyzer & LLMAnalyzer
        CodeAnalyzers --> |Condition| Minilexer
        CodeAnalyzers --> |Condition| Miniparser
    end
   subgraph Optimizer
       direction LR
       BaseOptimizer[Optimizer] --> LLMOptimizer[LLM Optimizer]
       LLMOptimizer[LLM Optimizer] --> OptimizedResult
       OptimizedResult[Result]
   end

    Analyzers --> |Condition| Deliver
    Analyzers --> |Condition| Tagger
    Deliver --> 3rdParty
    BaseOptimizer --> OptimizedResult
    OptimizedResult --> OutputBuilder
    Tagger --> |Tags| BaseOptimizer
    Analyzers --> |Endpoints| BaseOptimizer
    OutputBuilder --> Report:::highlight

    classDef highlight fill:#000,stroke:#333,stroke-width:4px;
{% end %}

## Project Goals

The primary goal of Noir is to bridge the gap between static code analysis and dynamic security testing. By providing a comprehensive and accurate list of an application's endpoints—including those that are hidden or undocumented—Noir enables DAST tools to perform more thorough and effective scans.

Noir serves as the critical link in DevSecOps pipelines, transforming source code analysis into actionable endpoint data that security tools can consume immediately.

In the future, we plan to expand our support for more languages and frameworks, improve the accuracy of our analysis, and further leverage AI and LLMs to enhance our capabilities.

## Contributing

OWASP Noir is an open-source project that thrives on community contributions. If you are interested in helping us improve the tool, please check out our [Contributing Guide](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md). We welcome contributions of all sizes, from fixing typos to adding major new features.

### Contributors

Thank you to everyone who has contributed to Noir! ♥️

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/docs/static/CONTRIBUTORS.svg)

## Code of Conduct

We are committed to fostering a welcoming and inclusive community. Please review our [Code of Conduct](https://github.com/owasp-noir/noir/blob/main/CODE_OF_CONDUCT.md) on our GitHub repository.

## Help and Feedback

If you have any questions, suggestions, or issues, please don't hesitate to reach out to us on the GitHub [discussions](https://github.com/orgs/owasp-noir/discussions) or [issues](https://github.com/owasp-noir/noir/issues) page.
