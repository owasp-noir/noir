+++
title = "SARIF"
description = "GitHub, GitLab, Azure DevOps와 CI/CD 통합을 위한 SARIF v2.1.0 출력을 생성합니다."
weight = 5
sort_by = "weight"

+++

CI/CD 통합을 위한 SARIF v2.1.0 (정적 분석 결과 교환 형식) 출력을 생성합니다.

## SARIF를 사용하는 이유?

*   보안 도구 생태계 전반에서 지원되는 OASIS 표준
*   GitHub Code Scanning, GitLab, Azure DevOps에서 기본 지원
*   심각도 수준 및 파일 위치 등 풍부한 메타데이터
*   파이프라인에서 자동화된 보안 게이트 구현 가능

## 사용법

SARIF 출력 생성:

```bash
noir -b . -f sarif --no-log
```

파일로 저장:

```bash
noir -b . -f sarif -o results.sarif --no-log
```

## 출력 예제

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

각 엔드포인트는 다음 정보와 함께 SARIF 결과로 보고됩니다:

*   **규칙 ID**: API 엔드포인트 발견 사항에 대한 `endpoint-discovery`
*   **수준**: `note` (정보 제공 발견 사항)
*   **메시지**: HTTP 메서드, URL 경로 및 발견된 매개변수
*   **위치**: 엔드포인트가 발견된 파일 경로 및 줄 번호

### 패시브 스캔 통합

패시브 스캔 기능(`-P` 또는 `--passive-scan`) 사용 시 보안 발견 사항이 심각도 매핑과 함께 SARIF 출력에 포함됩니다:

*   **Critical/High 심각도** → `error` 수준
*   **Medium 심각도** → `warning` 수준
*   **Low 심각도** → `note` 수준

각 패시브 스캔 규칙은 설명, 참조 및 작성자 정보를 포함하여 `rules` 배열에 포함됩니다.

## 통합 예제

### GitHub Code Scanning

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

```yaml
noir_scan:
  script:
    - noir -b . -f sarif -o gl-sast-report.json --no-log
  artifacts:
    reports:
      sast: gl-sast-report.json
```

### Azure DevOps

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

