+++
title = "Step 1: What is Noir?"
description = "OWASP Noir is an attack surface detector that identifies endpoints by static analysis."
weight = 1
sort_by = "weight"

+++

> **Goal**: Understand what Noir does before installing it.

Noir is an attack surface detector that analyzes source code to discover API endpoints, including shadow APIs and undocumented routes. It bridges SAST and DAST by feeding discovered endpoints directly into dynamic testing tools.

![noir-usage](./noir-usage.jpg)

## What Can Noir Do?

- **Find hidden endpoints** — Discovers shadow APIs, undocumented routes, and forgotten endpoints from source code
- **Support 50+ frameworks** — One tool for Rails, Django, Spring, Express, FastAPI, and many more
- **Use AI for unknown code** — LLMs detect endpoints even in unsupported frameworks
- **Feed into DAST tools** — Sends results directly to ZAP, Burp Suite, Caido
- **Export anywhere** — JSON, YAML, OpenAPI, SARIF, cURL, HTML reports, and more

## How Does It Work?

Point Noir at your source code and it automatically:

1. **Detects** which languages and frameworks your project uses
2. **Analyzes** the code to extract endpoints, parameters, and headers
3. **Reports** results in your preferred format

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

---

**Next step**: [Step 2: Install Noir](@/get_started/installation/index.md)
