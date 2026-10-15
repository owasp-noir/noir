+++
title = "GitHub Action"
description = "Run OWASP Noir in GitHub Actions workflows for endpoint discovery and optional passive security scanning."
weight = 6
sort_by = "weight"

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
      - uses: actions/checkout@v6

      - name: Run OWASP Noir
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: '.'

      - name: Display results
        run: echo '${{ steps.noir.outputs.endpoints }}' | jq .
~~~

- `base_path`: Directory to analyze (`-b/--base-path`)
- `endpoints`: The JSON result, for later steps to process

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
| `use_all_taggers` | Enable all taggers (`-T/--use-all-taggers`) | No | `false` |
| `use_taggers` | Enable specific taggers (`--use-taggers`) | No | `` |
| `include_path` | Add source file paths to `plain` output; JSON always has them (`--include-path`) | No | `false` |
| `verbose` | Verbose output (`--verbose`) | No | `false` |
| `debug` | Debug output (`-d/--debug`) | No | `false` |
| `concurrency` | Concurrency level (`--concurrency`) | No | `` |
| `exclude_codes` | Exclude HTTP response codes (comma‑separated) (`--exclude-codes`) | No | `` |
| `status_codes` | Display HTTP status codes for discovered endpoints (`--status-codes`) | No | `false` |
| `ai_provider` | AI provider prefix or full custom URL (`--ai-provider`) | No | `` |
| `ai_model` | AI model name (`--ai-model`) | No | `` |
| `ai_key` | AI API key (`--ai-key`) | No | `` |
| `ai_agent` | Enable agentic AI workflow (`--ai-agent`) | No | `false` |
| `probe` | Fire HTTP requests at discovered endpoints (`--probe`) | No | `false` |
| `probe_via` | Route probes through a proxy URL (`--probe-via`) | No | `` |
| `export_es` | Index endpoints in Elasticsearch or OpenSearch (`--export-es`) | No | `` |
| `export_webhook` | POST endpoint catalog as JSON to a webhook URL (`--export-webhook`) | No | `` |
| `diff_path` | Old code version path for diff analysis (`--diff-path`) | No | `` |
| `diff_ref` | Git revision to diff the checkout against, e.g. the pull request base; fetched if the checkout lacks it (`--diff-ref`) | No | `` |
| `fail_on` | Fail the step (exit code `3`) when the diff has any of `added`, `removed`, `changed`, `auth-removed` (`--fail-on`) | No | `` |
| `no_log` | Hide execution logs and show only results (`--no-log`) | No | `true` |

**Notes:**
- Pass boolean options as strings (`'true'`/`'false'`).
- `output_file` is relative to the workspace. Set it when a later step needs the report file. The step outputs are filled either way.
- `status_codes`, `exclude_codes`, `probe` and `probe_via` need `url`. Without it the scan stops with an error.
- With `jsonl`, the outputs below fold the lines into the same single document `json` produces.

## Outputs

| Name | Description |
|---|---|
| `endpoints` | The full Noir result document (`{"endpoints":[...],"passive_results":[...],"errors":[...]}`) when `format` is `json` or `jsonl`. Empty for other formats |
| `passive_results` | A JSON array of passive-scan findings when `format` is `json` or `jsonl`. `[]` when passive scan is off, found nothing, or the format is anything else |

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
name: Noir Passive Scan
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Run OWASP Noir with Passive Scanning
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: 'src'
          format: 'json'
          passive_scan: 'true'
          passive_scan_severity: 'medium'
          use_all_taggers: 'true'
          verbose: 'true'
          output_file: 'noir-results.json'

      - name: Process Results
        run: |
          echo "Endpoints discovered:"
          echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

          echo "Passive scan findings:"
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
      - uses: actions/checkout@v6

      - name: Run Noir for ${{ matrix.service }}
        id: noir
        uses: owasp-noir/noir@main
        with:
          base_path: '${{ matrix.service }}'
          format: 'json'
~~~

### Attack Surface Review on Pull Requests

Diff the pull request against its base branch, post the result as a comment, and fail the check when a route loses its authentication:

~~~yaml
name: Attack Surface Review
on: pull_request

permissions:
  contents: read
  pull-requests: write

jobs:
  noir-diff:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Diff the attack surface
        uses: owasp-noir/noir@main
        with:
          base_path: '.'
          diff_ref: ${{ github.event.pull_request.base.sha }}
          format: 'markdown-table'
          output_file: 'noir-diff.md'
          fail_on: 'auth-removed'

      - name: Comment on the pull request
        if: always()
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh pr comment "${{ github.event.pull_request.number }}" --body-file noir-diff.md
~~~

`actions/checkout` fetches a single commit by default. If `diff_ref` isn't in the checkout, the action fetches that revision before scanning. The step fails with exit code `3` when the diff matches `fail_on`, and the report file is still written, so the comment step above runs with `if: always()`. For inline annotations instead of a comment, use `format: 'sarif'` and upload the file with `github/codeql-action/upload-sarif`.

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

Status codes come from live requests, so `url` must point at a running instance of the app:

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    url: 'http://localhost:3000'
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

1. Turn on passive scanning (`passive_scan: 'true'`) to catch security issues early.
2. Cut noise with `passive_scan_severity` and `exclude_codes`.
3. JSON output already records each endpoint's source file. For `plain` output, set `include_path: 'true'`.
4. Add frameworks with `techs` when auto-detection misses them. Use `exclude_techs` to drop analyzers you don't need.
5. Keep results with `actions/upload-artifact`.

## Troubleshooting

**No endpoints found:**
- Check that `base_path` points to the source directory
- Check that the repository uses a supported framework
- Set `techs` explicitly

**Output too large or slow:**
- Write `format: 'jsonl'` to `output_file` (one endpoint per line)
- Narrow `base_path` or use `techs`/`exclude_techs`

**Hard to diagnose:**
- Set `debug: 'true'` or `verbose: 'true'` together with `no_log: 'false'`. `no_log` defaults to `true` and hides the logs

**HTTP status noise:**
- Disable with `status_codes: 'false'` or use `exclude_codes`

## Implementation Notes

- The action runs the `ghcr.io/owasp-noir/noir` Docker image. The image tag follows the ref you pin: `@v1.4.0` uses `1.4.0`, `@main` uses `main`, and a commit SHA uses `latest`. If the tag can't be pulled (for example, a branch with no published image), the action falls back to `latest` with a warning.
- Each input maps to one CLI flag.
- See supported technologies: `noir list techs`
