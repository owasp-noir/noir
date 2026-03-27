+++
title = "SARIF"
description = "GitHub, GitLab, Azure DevOps와 CI/CD 통합을 위한 SARIF v2.1.0 출력을 생성합니다."
weight = 5
sort_by = "weight"

+++

SARIF v2.1.0 (Static Analysis Results Interchange Format) 형식으로 결과를 출력합니다. GitHub Code Scanning, GitLab, Azure DevOps 등 주요 CI/CD 플랫폼에서 바로 읽을 수 있는 표준 형식입니다.

## 왜 SARIF인가?

*   보안 도구 생태계 전반에서 쓰이는 OASIS 표준
*   GitHub Code Scanning, GitLab, Azure DevOps에서 네이티브 지원
*   심각도, 파일 위치 등 풍부한 메타데이터 포함
*   파이프라인에서 보안 게이트를 자동화할 수 있음

## 사용법

SARIF 출력을 생성합니다.

```bash
noir -b . -f sarif --no-log
```

파일로 저장할 수도 있습니다.

```bash
noir -b . -f sarif -o results.sarif --no-log
```

## 출력 예제

SARIF 파일은 `runs` 배열로 구성됩니다. 각 run에는 도구 정보(`driver`의 이름, 버전), 분석 규칙, 그리고 `results`(엔드포인트별 소스 파일 위치와 줄 번호)가 들어갑니다.

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

## SARIF 기능

### 엔드포인트 발견

각 엔드포인트는 아래 정보와 함께 SARIF result로 보고됩니다.

*   **Rule ID**: `endpoint-discovery`
*   **Level**: `note` (정보성 발견)
*   **Message**: HTTP 메서드, URL 경로, 파라미터
*   **Location**: 엔드포인트가 정의된 파일 경로와 줄 번호

### 패시브 스캔 통합

패시브 스캔(`-P` 또는 `--passive-scan`)을 함께 쓰면 보안 발견 사항이 심각도에 따라 SARIF에 포함됩니다.

*   **Critical/High** → `error`
*   **Medium** → `warning`
*   **Low** → `note`

각 패시브 스캔 규칙은 설명, 참조, 작성자 정보와 함께 `rules` 배열에 추가됩니다.

## 통합 예제

### GitHub Code Scanning

SARIF 결과를 [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)에 업로드하면 리포지토리 Security 탭에서 바로 확인할 수 있습니다.

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

`.gitlab-ci.yml`에 아래 잡을 추가하면 GitLab Security Dashboard에 결과가 표시됩니다.

```yaml
noir_scan:
  script:
    - noir -b . -f sarif -o gl-sast-report.json --no-log
  artifacts:
    reports:
      sast: gl-sast-report.json
```

### Azure DevOps

Azure Pipelines에서 SARIF 파일을 빌드 아티팩트로 게시하면 SARIF SAST Scans Tab 확장에서 결과를 볼 수 있습니다.

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
