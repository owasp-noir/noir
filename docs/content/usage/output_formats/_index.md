+++
title = "Output Formats"
description = "Noir supports a wide range of output formats to help you make the most of your scan results. This section provides an overview of the available formats, including JSON, YAML, TOML, OpenAPI Specification (OAS), and more."
weight = 2
sort_by = "weight"

+++

Noir is built to be a versatile tool that can fit into any workflow. A key part of this flexibility is the ability to output scan results in a variety of formats. Whether you need a machine-readable format for automation or a human-readable one for manual review, Noir has you covered.

## Choosing the Right Format

| Use Case | Recommended Format | Flag |
|---|---|---|
| Integration with scripts/tools | [JSON](json/) | `-f json` |
| CI/CD security reporting | [SARIF](sarif/) | `-f sarif` |
| API documentation generation | [OpenAPI](openapi/) | `-f oas3` |
| Quick endpoint testing | [cURL](curl/) / HTTPie / PowerShell | `-f curl` |
| Human-readable review | [YAML](yaml/) | `-f yaml` |
| Configuration-style output | [More](more/) (TOML) | `-f toml` |
| Import into Postman | [More](more/) (Postman Collection) | `-f postman` |
| Visual report sharing | [HTML](html/) | `-f html` |
| API structure visualization | [Mermaid](mermaid/) | `-f mermaid` |
| Just list URLs or params | [More](more/) (Filters) | `-f only-url` |

## Available Formats

*   **[HTTP Client Commands](curl/)**: Generate executable cURL, HTTPie, and PowerShell commands for testing endpoints.
*   **[JSON and JSONL](json/)**: A widely used format that's perfect for integrating with other tools and scripts.
*   **[YAML](yaml/)**: A human-readable format that's great for configuration files and manual inspection.
*   **[OpenAPI Specification (OAS)](openapi/)**: Generate an OpenAPI document from your code to easily create API documentation or set up security testing.
*   **[SARIF](sarif/)**: Industry-standard format for security tool output with native CI/CD platform integration.
*   **[HTML Report](html/)**: Generate a comprehensive, visual HTML report of your scan results.
*   **[Mermaid Chart](mermaid/)**: Generate diagrams for visualizing your API structure.
*   **[Additional Formats](more/)**: Discover additional formats including TOML, JSONL, Postman collections, Markdown tables, and specialized filters.

By choosing the right output format, you can streamline your development process and make it easier to act on the insights provided by Noir.
