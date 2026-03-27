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
noir -b . -f sarif --no-log
```

Save to file:

```bash
noir -b . -f sarif -o results.sarif --no-log
```

## Example Output

A SARIF file has a `runs` array. Each run describes the tool (`driver` with name and version), the analysis rules, and the `results` — one entry per discovered endpoint with its source file location and line number.

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "OWASP Noir",
          "version": "0.28.0",
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

Each passive scan rule is added to the `rules` array with descriptions, references, and author info.

## Integration Examples

### GitHub Code Scanning

Upload SARIF results to [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning) so findings show up in your repo's Security tab:

```bash
# Generate SARIF output
noir -b . -f sarif -o noir-results.sarif --no-log

# Upload to GitHub (using GitHub CLI)
gh api /repos/:owner/:repo/code-scanning/sarifs \
  -F sarif=@noir-results.sarif \
  -F ref=refs/heads/main \
  -F commit_sha=$(git rev-parse HEAD)
```

### GitLab Security Dashboard

Add this job to `.gitlab-ci.yml` to surface findings in GitLab's Security Dashboard:

```yaml
noir_scan:
  script:
    - noir -b . -f sarif -o gl-sast-report.json --no-log
  artifacts:
    reports:
      sast: gl-sast-report.json
```

### Azure DevOps

Publish the SARIF file as a build artifact in Azure Pipelines. The SARIF SAST Scans Tab extension picks it up automatically:

```yaml
- script: noir -b . -f sarif -o noir.sarif --no-log
  displayName: 'Run Noir Scan'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: 'noir.sarif'
    ArtifactName: 'CodeAnalysisLogs'
```

## Additional Resources

*   [SARIF Specification v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
*   [GitHub Code Scanning Documentation](https://docs.github.com/en/code-security/code-scanning)
*   [GitLab SAST Documentation](https://docs.gitlab.com/ee/user/application_security/sast/)
*   [SARIF Tutorials](https://github.com/microsoft/sarif-tutorials)
