# OWASP Noir GitHub Action

This GitHub Action allows you to run OWASP Noir security analysis in your CI/CD pipeline to detect attack surfaces by static analysis.

## Features

- **Endpoint Detection**: Automatically discovers endpoints in your application code
- **Multiple Output Formats**: Supports JSON, YAML, plain text, and other formats
- **Passive Security Scanning**: Detects potential security issues in your code
- **Technology Detection**: Automatically identifies frameworks and technologies
- **Comprehensive Coverage**: Supports multiple programming languages and frameworks

## Usage

### Basic Example

```yaml
name: Security Analysis
on: [push, pull_request]

jobs:
  noir-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Run OWASP Noir
        id: noir
        uses: owasp-noir/noir@v0.28.0
        with:
          base_path: '.'

      - name: Display results
        run: echo '${{ steps.noir.outputs.endpoints }}' | jq .
```

### Advanced Example

```yaml
name: Comprehensive Security Analysis
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Run OWASP Noir with Passive Scanning
        id: noir
        uses: owasp-noir/noir@v0.28.0
        with:
          base_path: 'src'
          format: 'json'
          passive_scan: 'true'
          passive_scan_severity: 'medium'
          use_all_taggers: 'true'
          include_path: 'true'
          verbose: 'true'

      - name: Process Results
        run: |
          echo "🔍 Endpoints discovered:"
          echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

          echo "🚨 Security issues found:"
          echo '${{ steps.noir.outputs.passive_results }}' | jq '. | length'

      - name: Save detailed results
        uses: actions/upload-artifact@v4
        with:
          name: security-analysis-results
          path: noir-results.json
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `base_path` | The base path to analyze for endpoints | Yes | `.` |
| `url` | Set base URL for endpoints | No | `` |
| `format` | Output format (json, yaml, plain, etc.) | No | `json` |
| `output_file` | Write results to file | No | `` |
| `techs` | Specify technologies to use | No | `` |
| `exclude_techs` | Specify technologies to exclude | No | `` |
| `passive_scan` | Enable passive security scanning | No | `false` |
| `passive_scan_severity` | Minimum severity level (critical, high, medium, low) | No | `high` |
| `use_all_taggers` | Activate all taggers for full coverage | No | `false` |
| `use_taggers` | Activate specific taggers | No | `` |
| `include_path` | Include file paths in results | No | `false` |
| `verbose` | Enable verbose output | No | `false` |
| `debug` | Enable debug messages | No | `false` |
| `concurrency` | Set concurrency level | No | `` |
| `exclude_codes` | Exclude HTTP response codes (comma-separated) | No | `` |
| `status_codes` | Display HTTP status codes | No | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `endpoints` | JSON formatted result of endpoint analysis |
| `passive_results` | JSON formatted result of passive scan (if enabled) |

## Supported Technologies

OWASP Noir supports analysis of applications built with:

- **Languages**: Crystal, Ruby, JavaScript/TypeScript, Python, PHP, Java, Go, C#, and more
- **Frameworks**: Rails, Sinatra, Express.js, Django, Flask, Laravel, Spring, Gin, ASP.NET, and many others
- **API Formats**: REST, GraphQL, gRPC
- **Frontend Frameworks**: React, Vue.js, Angular, Svelte

For a complete list, run: `noir --list-techs`

## Examples by Language/Framework

### Ruby on Rails

```yaml
- uses: owasp-noir/noir@v0.28.0
  with:
    base_path: '.'
    techs: 'rails'
    passive_scan: 'true'
```

### Node.js/Express

```yaml
- uses: owasp-noir/noir@v0.28.0
  with:
    base_path: 'src'
    techs: 'express'
    format: 'json'
```

### Python/Django

```yaml
- uses: owasp-noir/noir@v0.28.0
  with:
    base_path: '.'
    techs: 'django'
    passive_scan: 'true'
    passive_scan_severity: 'medium'
```

## Security Best Practices

1. **Enable Passive Scanning**: Use `passive_scan: 'true'` to detect security issues
2. **Set Appropriate Severity**: Use `passive_scan_severity` to control noise level
3. **Use All Taggers**: Enable `use_all_taggers: 'true'` for comprehensive analysis
4. **Include Paths**: Enable `include_path: 'true'` for easier issue tracking
5. **Save Results**: Use `actions/upload-artifact` to preserve analysis results

## Troubleshooting

### Common Issues

1. **No endpoints found**: Ensure `base_path` points to your source code directory
2. **Technology not detected**: Use `techs` input to specify your framework explicitly
3. **Large output**: Use `format: 'jsonl'` for streaming large results

### Debug Mode

Enable debug output for troubleshooting:

```yaml
- uses: owasp-noir/noir@v0.28.0
  with:
    base_path: '.'
    debug: 'true'
    verbose: 'true'
```

## License

This action is part of the OWASP Noir project and is licensed under the MIT License.

## Contributing

Contributions are welcome! Please see the [CONTRIBUTING.md](CONTRIBUTING.md) file in the main repository.
