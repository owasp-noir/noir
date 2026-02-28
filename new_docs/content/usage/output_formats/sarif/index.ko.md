+++
title = "SARIF"
description = "SARIF(정적 분석 결과 교환 형식) v2.1.0로 스캔 결과를 생성하는 방법을 배워보세요. GitHub, GitLab, Azure DevOps와 같은 CI/CD 플랫폼과 원활하게 통합되는 보안 도구 출력용 업계 표준 형식입니다."
weight = 5
sort_by = "weight"

+++

SARIF(정적 분석 결과 교환 형식)는 정적 분석 도구의 출력을 나타내기 위한 OASIS 표준입니다. Noir는 SARIF v2.1.0 호환 출력을 생성할 수 있어 스캔 결과를 최신 CI/CD 플랫폼 및 보안 대시보드와 쉽게 통합할 수 있습니다.

## SARIF를 사용하는 이유는?

*   **표준 준수**: SARIF는 보안 도구 생태계 전반에서 널리 지원되는 OASIS 표준입니다.
*   **CI/CD 통합**: GitHub Code Scanning, GitLab Security Dashboard, Azure DevOps 등에서 기본 지원합니다.
*   **풍부한 메타데이터**: 심각도 수준, 파일 위치, 규칙 설명 등 발견 사항에 대한 자세한 정보가 포함됩니다.
*   **기계 판독 가능**: 구조화된 형식으로 파이프라인에서 자동화된 보안 게이트 및 정책 적용이 가능합니다.

## SARIF 출력 생성 방법

Noir를 실행할 때 `-f sarif` 또는 `--format sarif` 플래그를 사용하여 SARIF 형식으로 스캔 결과를 얻을 수 있습니다. 출력을 깔끔하게 유지하려면 `--no-log` 플래그를 사용하는 것이 좋습니다.

```bash
noir -b . -f sarif --no-log
```

보안 플랫폼에 업로드하기 위해 출력을 파일로 저장할 수도 있습니다:

```bash
noir -b . -f sarif -o results.sarif --no-log
```

## SARIF 출력 예시

다음은 SARIF 출력의 샘플입니다:

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
                "text": "정적 분석을 통해 발견된 API 엔드포인트"
              },
              "fullDescription": {
                "text": "이 규칙은 정적 코드 분석을 통해 발견된 API 엔드포인트, HTTP 메서드 및 매개변수를 식별합니다"
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
            "text": "GET /api/users/:id (매개변수: path: id)"
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
            "text": "POST /api/users (매개변수: json: username, json: email)"
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

## Noir의 SARIF 기능

### 엔드포인트 발견

발견된 각 엔드포인트는 다음과 같은 SARIF 결과로 보고됩니다:

*   **규칙 ID**: API 엔드포인트 발견 사항에 대한 `endpoint-discovery`
*   **수준**: `note` (정보 제공 발견 사항)
*   **메시지**: HTTP 메서드, URL 경로 및 발견된 매개변수
*   **위치**: 엔드포인트가 발견된 파일 경로 및 줄 번호

### 수동 스캔 통합

Noir의 수동 스캔 기능(`-P` 또는 `--passive-scan`)을 사용하면 보안 발견 사항이 적절한 심각도 매핑과 함께 SARIF 출력에 자동으로 포함됩니다:

*   **Critical/High 심각도** → `error` 수준
*   **Medium 심각도** → `warning` 수준
*   **Low 심각도** → `note` 수준

각 수동 스캔 규칙은 설명, 참조 및 작성자 정보를 포함한 완전한 메타데이터와 함께 `rules` 배열에 포함됩니다.

## 통합 예시

### GitHub Code Scanning

SARIF 결과를 GitHub Code Scanning에 업로드:

```bash
# SARIF 출력 생성
noir -b . -f sarif -o noir-results.sarif --no-log

# GitHub에 업로드 (GitHub CLI 사용)
gh api /repos/:owner/:repo/code-scanning/sarifs \
  -F sarif=@noir-results.sarif \
  -F ref=refs/heads/main \
  -F commit_sha=$(git rev-parse HEAD)
```

### GitLab Security Dashboard

GitLab CI/CD 파이프라인에 Noir의 SARIF 출력 포함:

```yaml
noir_scan:
  script:
    - noir -b . -f sarif -o gl-sast-report.json --no-log
  artifacts:
    reports:
      sast: gl-sast-report.json
```

### Azure DevOps

Azure Pipelines에서 SARIF 결과 게시:

```yaml
- script: noir -b . -f sarif -o noir.sarif --no-log
  displayName: 'Noir 스캔 실행'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: 'noir.sarif'
    ArtifactName: 'CodeAnalysisLogs'
```

## 추가 리소스

*   [SARIF 명세 v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
*   [GitHub Code Scanning 문서](https://docs.github.com/en/code-security/code-scanning)
*   [GitLab SAST 문서](https://docs.gitlab.com/ee/user/application_security/sast/)
*   [SARIF 튜토리얼](https://github.com/microsoft/sarif-tutorials)

SARIF 출력을 사용하면 기존 보안 워크플로에 Noir를 원활하게 통합하고 최신 DevSecOps 플랫폼이 제공하는 풍부한 시각화 및 추적 기능을 활용할 수 있습니다.
