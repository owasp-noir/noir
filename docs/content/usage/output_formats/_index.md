+++
title = "Output Formats"
description = "The output formats Noir can emit: JSON, YAML, TOML, OpenAPI (OAS), SARIF, HTML, and more."
weight = 2
sort_by = "weight"

+++

Scan results can come out in whatever shape the next step needs: machine-readable for automation, human-readable for review. Pick a format with `-f`.

## Choosing the Right Format

| Use Case | Recommended Format | Flag |
|---|---|---|
| Integration with scripts/tools | [JSON](json/) | `-f json` |
| CI/CD security reporting | [SARIF](sarif/) | `-f sarif` |
| API documentation generation | [OpenAPI](openapi/) | `-f oas3` |
| Quick endpoint testing | [cURL](curl/) / HTTPie / PowerShell | `-f curl` |
| Launching mobile entry points | [ADB](curl/#adb-android) (Android) / [simctl](curl/#simctl-ios) (iOS) | `-f adb` / `-f simctl` |
| Human-readable review | [YAML](yaml/) | `-f yaml` |
| Configuration-style output | [More](more/) (TOML) | `-f toml` |
| Import into Postman | [More](more/) (Postman Collection) | `-f postman` |
| Visual report sharing | [HTML](html/) | `-f html` |
| API structure visualization | [Mermaid](mermaid/) | `-f mermaid` |
| Just list URLs or params | [More](more/) (Filters) | `-f only-url` |

## Request body coverage by format

Not every format turns every `param_type` into a wire body. Use this as a quick map (✅ = emitted as a request body / multipart part, ➖ = kept on the endpoint record only, or not applicable):

| `param_type` | `json` / `yaml` / plain | `oas2` / `oas3` | `postman` | `curl` / `httpie` / `powershell` / HTML copy-as-curl |
|---|---|---|---|---|
| `json` | ✅ (typed field) | ✅ `application/json` | ✅ raw JSON | ✅ JSON body |
| `form` | ✅ (typed field) | ✅ urlencoded or multipart | ✅ `urlencoded` | ✅ urlencoded body |
| `file` | ✅ (typed field) | ✅ multipart `format: binary` | ✅ `formdata` file | ✅ multipart upload |
| `xml` | ✅ (typed field) | ✅ `application/xml` | ✅ raw XML (`<name/>` if empty) | ➖ not baked into the command — use OAS / Postman / JSON |

Details: [cURL](curl/#xml-request-bodies), [OpenAPI](openapi/), [Postman](more/#postman-collection).

## Available Formats

*   **[HTTP Client Commands](curl/)**: Executable cURL, HTTPie, and PowerShell commands for testing endpoints, plus [ADB](curl/#adb-android) (Android) and [simctl](curl/#simctl-ios) (iOS) commands for launching mobile deep links, intents, and content providers.
*   **[JSON and JSONL](json/)**: For piping into other tools and scripts.
*   **[YAML](yaml/)**: Easier than JSON to read during manual review.
*   **[OpenAPI Specification (OAS)](openapi/)**: An OpenAPI document generated from your code, for API documentation or import into security tools.
*   **[SARIF](sarif/)**: The standard format CI/CD security dashboards ingest.
*   **[HTML Report](html/)**: A self-contained, interactive HTML report.
*   **[Mermaid Chart](mermaid/)**: Diagrams of the API structure.
*   **[Additional Formats](more/)**: TOML, JSONL, Postman collections, Markdown tables, and output filters.
