+++
title = "GitHub Action"
description = "Run OWASP Noir in GitHub Actions workflows for endpoint discovery and optional passive security scanning."
weight = 6
sort_by = "weight"

[extra]
+++

Run OWASP Noir in GitHub Actions for endpoint discovery and optional passive security scanning during CI.

## Quick Start

Minimal workflow:

~~~yaml
name: Noir Security Analysis
on: [push, pull_request]

jobs:
  noir-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Run OWASP Noir
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: '.'

      - name: Display results
        run: echo '${{ steps.noir.outputs.endpoints }}' | jq .
~~~

- `base_path`: Directory to analyze (`-b/--base-path`)
- `endpoints`: JSON output for post-processing

## Inputs

| Name | Description | Required | Default |
|---|---|---|---|
| `base_path` | Base path to analyze (equivalent to `-b/--base-path`) | Yes | `.` |
| `url` | Base URL for endpoints (equivalent to `-u/--url`) | No | `` |
| `format` | Output format (`plain`, `yaml`, `json`, `jsonl`, `markdown-table`, `curl`, `httpie`, `oas2`, `oas3`, etc.) | No | `json` |
| `output_file` | Write results to a file (equivalent to `-o/--output`) | No | `` |
| `techs` | Technologies to include (equivalent to `-t/--techs`) | No | `` |
| `exclude_techs` | Technologies to exclude (`--exclude-techs`) | No | `` |
| `passive_scan` | Enable passive security scan (`-P/--passive-scan`) | No | `false` |
| `passive_scan_severity` | Minimum severity for passive scan (`critical`, `high`, `medium`, `low`) | No | `high` |
| `use_all_taggers` | Enable all taggers for comprehensive analysis (`-T/--use-all-taggers`) | No | `false` |
| `use_taggers` | Enable specific taggers (`--use-taggers`) | No | `` |
| `include_path` | Include source file paths in results (`--include-path`) | No | `false` |
| `include_techs` | Include technology information in results (`--include-techs`) | No | `false` |
| `verbose` | Verbose output (`--verbose`) | No | `false` |
| `debug` | Debug output (`-d/--debug`) | No | `false` |
| `concurrency` | Concurrency level (`--concurrency`) | No | `` |
| `exclude_codes` | Exclude HTTP response codes (comma‑separated) (`--exclude-codes`) | No | `` |
| `status_codes` | Display HTTP status codes for discovered endpoints (`--status-codes`) | No | `false` |

**Notes:**
- Pass boolean options as strings (`'true'`/`'false'`)
- `output_file` writes to file and provides outputs

## Outputs

| Name | Description |
|---|---|
| `endpoints` | JSON‑formatted endpoint analysis |
| `passive_results` | JSON‑formatted passive scan findings (present when `passive_scan` is enabled) |

Consuming outputs:

~~~yaml
- name: Count endpoints
  run: echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

- name: Show passive issues (if enabled)
  run: echo '${{ steps.noir.outputs.passive_results }}' | jq '. | length'
~~~

## Examples

### Advanced Scan

~~~yaml
name: Comprehensive Security Analysis
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Run OWASP Noir with Passive Scanning
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: 'src'
          format: 'json'
          passive_scan: 'true'
          passive_scan_severity: 'medium'
          use_all_taggers: 'true'
          include_path: 'true'
          include_techs: 'true'
          verbose: 'true'
          output_file: 'noir-results.json'

      - name: Process Results
        run: |
          echo "🔍 Endpoints discovered:"
          echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

          echo "🚨 Security issues found:"
          echo '${{ steps.noir.outputs.passive_results }}' | jq '. | length'

      - name: Save detailed results
        uses: actions/upload-artifact@v4
        with:
          name: noir-security-results
          path: noir-results.json
~~~

### Monorepo Matrix

~~~yaml
name: Monorepo Noir
on: [push, pull_request]

jobs:
  noir:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [service-a, service-b, service-c]
    steps:
      - uses: actions/checkout@v5

      - name: Run Noir for ${{ matrix.service }}
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: '${{ matrix.service }}'
          format: 'json'
          include_path: 'true'
~~~

### Framework-Specific Scans

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    techs: 'rails'           # ruby on rails
    passive_scan: 'true'
~~~

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: 'src'
    techs: 'express'         # node.js express
    format: 'json'
~~~

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    techs: 'django'          # python django
    passive_scan: 'true'
    passive_scan_severity: 'medium'
~~~

### Status Code Configuration

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    status_codes: 'true'       # include HTTP status codes
    exclude_codes: '404,429'   # suppress noisy codes
~~~

### Alternate Formats

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    format: 'markdown-table'   # or: 'curl', 'httpie', 'yaml', 'jsonl', 'oas3'
    output_file: 'noir.md'
~~~

## Best Practices

1. Enable passive scanning (`passive_scan: 'true'`) to surface security smells early.
2. Tune noise with `passive_scan_severity` and `exclude_codes`.
3. Include paths (`include_path: 'true'`) to speed up triage and code navigation.
4. Pin frameworks with `techs` when auto‑detection isn’t enough; use `exclude_techs` to avoid irrelevant analyzers.
5. Persist results with `actions/upload-artifact`

## Troubleshooting

**No endpoints found:**
- Verify `base_path` points to source directory
- Check repository contains supported frameworks
- Specify `techs` explicitly

**Output too large or slow:**
- Use `format: 'jsonl'` for streaming
- Narrow `base_path` or use `techs`/`exclude_techs`

**Hard to diagnose:**
- Enable `debug: 'true'` and `verbose: 'true'`
- Use `include_path: 'true'` and `include_techs: 'true'` for traceability

**HTTP status noise:**
- Disable with `status_codes: 'false'` or use `exclude_codes`



## Implementation Notes

- Runs in Docker container for consistency
- Inputs map directly to CLI flags
- See supported technologies: `noir --list-techs`
