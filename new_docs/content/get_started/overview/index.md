+++
title = "Overview"
description = "Learn what OWASP Noir is, how it works, and what its goals are. This page provides a high-level introduction to the project and its key features."
weight = 1
sort_by = "weight"

+++

Noir bridges SAST and DAST by analyzing source code to discover endpoints—including shadow APIs, deprecated routes, and hidden paths that other tools miss.

Using source code as the single source of truth, Noir delivers comprehensive attack surface data that integrates with DAST tools, eliminating blind spots in your DevSecOps pipeline.

## Key Capabilities

- **Attack Surface Discovery**: Identifies complete attack surface including hidden endpoints and shadow APIs
- **AI-Powered Analysis**: Uses LLMs to detect endpoints in unsupported languages and frameworks
- **SAST-to-DAST Bridge**: Provides discovered endpoints to DAST tools for comprehensive security scans
- **DevSecOps Ready**: Integrates with CI/CD pipelines and tools like ZAP, Burp Suite, and Caido
- **Multi-Format Output**: Exports in JSON, YAML, OpenAPI, and other formats

[GitHub](https://github.com/owasp-noir/noir) | [OWASP Project Page](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## How It Works

Noir is built with [Crystal](https://crystal-lang.org) and uses these components:

*   **Detectors**: Identify technologies in the codebase
*   **Analyzers**: Parse code to find endpoints and parameters
*   **LLM Analyzer**: Discover endpoints using AI for unsupported frameworks
*   **Passive Scanner & Tagger**: Identify vulnerabilities and add contextual tags
*   **Deliver**: Send results to external tools
*   **Output Builder**: Generate reports in multiple formats

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

Bridge static code analysis and dynamic security testing by providing comprehensive endpoint discovery—including hidden and undocumented endpoints—enabling more effective DAST scans.

Future plans include expanding language support, improving analysis accuracy, and enhancing AI capabilities.

## Contributing

Noir is open-source and welcomes contributions. See our [Contributing Guide](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) for details.

### Contributors

Thank you to everyone who has contributed to Noir! ♥️

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/docs/static/CONTRIBUTORS.svg)

## Code of Conduct

Review our [Code of Conduct](https://github.com/owasp-noir/noir/blob/main/CODE_OF_CONDUCT.md) on GitHub.

## Help and Feedback

Questions or feedback? Use GitHub [discussions](https://github.com/orgs/owasp-noir/discussions) or [issues](https://github.com/owasp-noir/noir/issues).
