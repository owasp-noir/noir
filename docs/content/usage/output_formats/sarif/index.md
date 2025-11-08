+++
title = "SARIF"
description = "Learn how to generate scan results in SARIF (Static Analysis Results Interchange Format) v2.1.0, the industry-standard format for security tool output that integrates seamlessly with CI/CD platforms like GitHub, GitLab, and Azure DevOps."
weight = 5
sort_by = "weight"

[extra]
+++

SARIF (Static Analysis Results Interchange Format) is an OASIS standard for representing the output of static analysis tools. Noir can generate SARIF v2.1.0 compliant output, making it easy to integrate your scan results with modern CI/CD platforms and security dashboards.

## Why Use SARIF?

*   **Standards Compliant**: SARIF is an OASIS standard widely supported across the security tooling ecosystem.
*   **CI/CD Integration**: Native support in GitHub Code Scanning, GitLab Security Dashboard, Azure DevOps, and more.
*   **Rich Metadata**: Includes detailed information about findings, including severity levels, file locations, and rule descriptions.
*   **Machine Readable**: Structured format enables automated security gates and policy enforcement in pipelines.

## How to Generate SARIF Output

To get your scan results in SARIF format, use the `-f sarif` or `--format sarif` flag when running Noir. It's recommended to use the `--no-log` flag to keep the output clean.

```bash
noir -b . -f sarif --no-log
```

You can also save the output to a file for uploading to security platforms:

```bash
noir -b . -f sarif -o results.sarif --no-log
```

## Example SARIF Output

Here is a sample of what the SARIF output looks like:

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "OWASP Noir",
          "version": "0.25.0",
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

When using Noir's passive scan feature (`-P` or `--passive-scan`), security findings are automatically included in the SARIF output with proper severity mapping:

*   **Critical/High severity** → `error` level
*   **Medium severity** → `warning` level
*   **Low severity** → `note` level

Each passive scan rule is included in the `rules` array with complete metadata including descriptions, references, and author information.

## Integration Examples

### GitHub Code Scanning

Upload your SARIF results to GitHub Code Scanning:

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

Include Noir's SARIF output in your GitLab CI/CD pipeline:

```yaml
noir_scan:
  script:
    - noir -b . -f sarif -o gl-sast-report.json --no-log
  artifacts:
    reports:
      sast: gl-sast-report.json
```

### Azure DevOps

Publish SARIF results in Azure Pipelines:

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

By using SARIF output, you can seamlessly integrate Noir into your existing security workflows and take advantage of the rich visualization and tracking features offered by modern DevSecOps platforms.
