+++
title = "Overview"
description = "Learn what OWASP Noir is, how it works, and what its goals are. This page provides a high-level introduction to the project and its key features."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir is an open-source tool designed to help security professionals and developers identify the attack surface of their applications. By performing static analysis on source code, Noir can discover API endpoints, web pages, and other potential entry points that could be targeted by attackers.

This makes it an invaluable tool for white-box security testing and for building robust security pipelines.

[GitHub](https://github.com/owasp-noir/noir) | [OWASP Project Page](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## How It Works

Noir is built with the [Crystal](https://crystal-lang.org) programming language and is composed of several key components that work together to analyze code:

*   **Detectors**: Identify the technologies used in a codebase.
*   **Analyzers**: Parse the code to find endpoints, parameters, and other interesting information.
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

    PassiveScan --> |Results| OutputBuilder

    Detectors --> |Techs| Analyzers

    subgraph Analyzers
        direction LR
        CodeAnalyzers & FileAnalyzer & LLMAnalyzer
        CodeAnalyzers --> |Condition| Minilexer
        CodeAnalyzers --> |Condition| Miniparser
    end

    Analyzers --> |Condition| Deliver
    Analyzers --> |Condition| Tagger
    Deliver --> 3rdParty
    Tagger --> |Tags| OutputBuilder
    Analyzers --> |Endpoints| OutputBuilder
    OutputBuilder --> Report:::highlight

    classDef highlight fill:#f9f,stroke:#333,stroke-width:4px;
{% end %}

## Project Goals

The primary goal of Noir is to bridge the gap between static code analysis and dynamic security testing. By providing a comprehensive and accurate list of an application's endpoints, Noir enables DAST tools to perform more thorough and effective scans.

In the future, we plan to expand our support for more languages and frameworks, improve the accuracy of our analysis, and further leverage AI and LLMs to enhance our capabilities.

## Contributing

OWASP Noir is an open-source project that thrives on community contributions. If you are interested in helping us improve the tool, please check out our [Contributing Guide](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md). We welcome contributions of all sizes, from fixing typos to adding major new features.

### Contributors

Thank you to everyone who has contributed to Noir! ♥️

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/CONTRIBUTORS.svg)

## Code of Conduct

We are committed to fostering a welcoming and inclusive community. Please review our [Code of Conduct](https://github.com/owasp-noir/noir/blob/main/CODE_OF_CONDUCT.md) on our GitHub repository.

## Help and Feedback

If you have any questions, suggestions, or issues, please don't hesitate to reach out to us on the GitHub [discussions](https://github.com/orgs/owasp-noir/discussions) or [issues](https://github.com/owasp-noir/noir/issues) page.
