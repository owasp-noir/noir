+++
title = "Overview"
description = "OWASP Noir is an attack surface detector that identifies endpoints by static analysis."
weight = 1
sort_by = "weight"

+++

Noir is an attack surface detector that analyzes source code to discover API endpoints, including shadow APIs and undocumented routes. It bridges SAST and DAST by feeding discovered endpoints directly into dynamic testing tools.

## Key Capabilities

- **Attack Surface Discovery** — Uncovers hidden endpoints, shadow APIs, and undocumented routes from source code
- **Multi-Language** — Supports 50+ languages and frameworks with a single tool
- **AI-Powered** — Uses LLMs to detect endpoints even in unsupported frameworks
- **SAST-to-DAST Bridge** — Feeds results into ZAP, Burp Suite, Caido, and other DAST tools
- **Flexible Output** — Exports as JSON, YAML, OpenAPI, SARIF, cURL, and more

[GitHub](https://github.com/owasp-noir/noir) | [OWASP Project Page](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## How It Works

Noir is built with [Crystal](https://crystal-lang.org) and processes code through these stages:

1. **Detectors** identify technologies in the codebase
2. **Analyzers** parse code to extract endpoints and parameters
3. **LLM Analyzer** discovers endpoints using AI for unsupported frameworks
4. **Passive Scanner & Tagger** identify vulnerabilities and add contextual tags
5. **Deliver** sends results to external tools (ZAP, Burp, etc.)
6. **Output Builder** generates reports in the desired format

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

## Contributing

Noir is open-source and welcomes contributions. See the [Contributing Guide](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md) for details.

### Contributors

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/docs/static/CONTRIBUTORS.svg)
