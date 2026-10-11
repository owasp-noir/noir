+++
title = "SARIF"
description = "Generate SARIF v2.1.0 output for CI/CD integration with GitHub, GitLab, and Azure DevOps."
weight = 5
sort_by = "weight"

+++

Output results as SARIF v2.1.0 (Static Analysis Results Interchange Format). This is the standard format that GitHub Code Scanning, GitLab, and Azure DevOps can ingest natively.

## Why SARIF?

*   OASIS standard supported across the security tooling ecosystem
*   Native support in GitHub Code Scanning, GitLab, Azure DevOps
*   Rich metadata with severity levels and file locations
*   Enables automated security gates in pipelines

## Usage

Generate SARIF output:

```bash
noir scan . -f sarif --no-log
```

Save to file:

```bash
noir scan . -f sarif -o results.sarif --no-log
```

## Example Output

A SARIF file has a `runs` array. Each run describes the tool (`driver` with name and version), the analysis rules, the `results` (one entry per discovered endpoint with its source file location and line number), and an `invocations` entry whose `executionSuccessful` mirrors the `errors` key of the [JSON output](../json/): `false` when any analyzer failed or skipped a file.

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "OWASP Noir",
          "version": "1.4.0",
          "informationUri": "https://github.com/owasp-noir/noir",
          "rules": [
            {
              "id": "endpoint-discovery",
              "name": "Endpoint Discovery",
              "shortDescription": {
                "text": "Discovered API endpoints through static analysis"
              },
              "fullDescription": {
                "text": "This rule identifies API endpoints, their HTTP methods, and parameters discovered through static code analysis"
              },
              "defaultConfiguration": {
                "level": "note"
              },
              "helpUri": "https://github.com/owasp-noir/noir"
            }
          ]
        }
      },
      "results": [
        {
          "ruleId": "endpoint-discovery",
          "ruleIndex": 0,
          "level": "note",
          "message": {
            "text": "GET /api/users/:id (Parameters: path: id)"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/routes.cr"
                },
                "region": {
                  "startLine": 42
                }
              }
            }
          ]
        },
        {
          "ruleId": "endpoint-discovery",
          "ruleIndex": 0,
          "level": "note",
          "message": {
            "text": "POST /api/users (Parameters: json: username, json: email)"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/routes.cr"
                },
                "region": {
                  "startLine": 56
                }
              }
            }
          ]
        }
      ],
      "invocations": [
        {
          "executionSuccessful": true
        }
      ]
    }
  ]
}
```

## SARIF Features in Noir

### Endpoint Discovery

Each discovered endpoint is reported as a SARIF result with:

*   **Rule ID**: `endpoint-discovery` for API endpoint findings
*   **Level**: `note` (informational finding)
*   **Message**: HTTP method, URL path, and discovered parameters
*   **Location**: File path and line number where the endpoint was found

### Passive Scan Integration

When using passive scan (`-P` or `--passive-scan`), security findings are included in the SARIF output with severity mapping:

*   **Critical/High severity** → `error` level
*   **Medium severity** → `warning` level
*   **Low severity** → `note` level
*   Any other severity → `none`

By default `-P` keeps only high and critical findings. Lower the bar with `--passive-scan-severity medium` (or `low`) to see the rest.

Each passive scan rule is added to the `rules` array with its name and description, and its first reference as `helpUri`.

### Callees and AI Context

When endpoints carry callees (`--include callee`) or AI review context (`--ai-context`), each endpoint result gets them under `properties.noir.callees` and `properties.noir.ai_context`.

### Diff Mode

With `--diff-path` or `--diff-ref`, `-f sarif` reports only the new attack surface, using the rules `diff-endpoint-added`, `diff-params-added` and `diff-auth-removed`. Removed routes have no line to annotate in the new tree, so they are left out. See [Diff](@/usage/more_features/diff/index.md).

## Integration Examples

### GitHub Code Scanning

Upload SARIF results to [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning) so findings show up in your repo's Security tab:

```bash
# Generate SARIF output
noir scan . -f sarif -o noir-results.sarif --no-log

# Upload to GitHub with the GitHub CLI (the API takes the file gzipped and base64-encoded)
gh api /repos/:owner/:repo/code-scanning/sarifs \
  -f sarif="$(gzip -c noir-results.sarif | base64 | tr -d '\n')" \
  -f ref=refs/heads/main \
  -f commit_sha="$(git rev-parse HEAD)"
```

### GitLab Security Dashboard

GitLab reads SARIF through the `sarif` report type (GitLab Ultimate, recent versions). The `sast` report type expects GitLab's own JSON schema, so don't point it at a SARIF file. Add this job to `.gitlab-ci.yml`:

```yaml
noir_scan:
  script:
    - noir scan . -f sarif -o noir.sarif --no-log
  artifacts:
    reports:
      sarif: noir.sarif
```

### Azure DevOps

Publish the SARIF file as a build artifact in Azure Pipelines. The SARIF SAST Scans Tab extension picks it up automatically:

```yaml
- script: noir scan . -f sarif -o noir.sarif --no-log
  displayName: 'Run Noir Scan'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: 'noir.sarif'
    ArtifactName: 'CodeAnalysisLogs'
```

## Additional Resources

*   [SARIF Specification v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
*   [GitHub Code Scanning Documentation](https://docs.github.com/en/code-security/code-scanning)
*   [GitLab SARIF reports](https://docs.gitlab.com/user/application_security/detect/sarif/)
*   [SARIF Tutorials](https://github.com/microsoft/sarif-tutorials)
