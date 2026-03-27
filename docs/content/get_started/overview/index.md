+++
title = "What is Noir?"
description = "OWASP Noir is an attack surface detector that identifies endpoints by static analysis."
weight = 1
sort_by = "weight"

+++

Noir is an open-source attack surface detector. It reads your source code and discovers all API endpoints — including shadow APIs and undocumented routes that may not appear in your documentation.

Security teams use Noir to find what attackers would look for: forgotten endpoints, exposed parameters, and hidden routes that slip through code reviews. Developers use it to keep API documentation accurate and feed endpoint data into testing pipelines.

![noir-usage](./noir-usage.jpg)

## What Can Noir Do?

**Find what's hidden.** Noir statically analyzes source code to extract every endpoint, parameter, header, and cookie — even the ones nobody documented.

**Work with any stack.** A single binary supports 50+ frameworks across Crystal, Go, Java, JavaScript, Kotlin, PHP, Python, Ruby, Rust, Swift, and more. No plugins or per-language setup needed.

**Bring AI to the table.** For frameworks Noir doesn't natively support, connect an LLM (OpenAI, Ollama, etc.) and let AI analyze the code for you.

**Bridge SAST and DAST.** Noir discovers endpoints from source code (SAST side), then feeds them directly into ZAP, Burp Suite, or Caido for dynamic testing (DAST side). This closes the gap where DAST tools miss endpoints they don't know about.

**Export in any format.** Results come out as JSON, YAML, OpenAPI specs, SARIF for CI/CD, cURL commands, HTML reports, or Postman collections — whatever your workflow needs.

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

**Next**: [Install Noir](@/get_started/installation/index.md)
