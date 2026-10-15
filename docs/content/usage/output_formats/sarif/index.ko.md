+++
title = "SARIF"
description = "GitHub, GitLab, Azure DevOps와 CI/CD 통합을 위한 SARIF v2.1.0 출력을 생성합니다."
weight = 5
sort_by = "weight"

+++

결과를 SARIF v2.1.0(Static Analysis Results Interchange Format)으로 출력합니다. GitHub Code Scanning, GitLab, Azure DevOps가 읽을 수 있는 OASIS 표준입니다. 결과마다 심각도와 파일 위치가 들어 있어 파이프라인에서 게이트 조건으로 쓸 수 있습니다.

## 사용법

SARIF 출력을 생성합니다.

```bash
noir scan . -f sarif --no-log
```

파일로 저장할 수도 있습니다.

```bash
noir scan . -f sarif -o results.sarif --no-log
```

## 출력 예제

SARIF 파일은 `runs` 배열로 구성됩니다. 각 run에는 도구 정보(`driver`의 이름, 버전), 분석 규칙, `results`(엔드포인트별 소스 파일 위치와 줄 번호), 그리고 `invocations`가 들어갑니다. `invocations`의 `executionSuccessful`은 [JSON 출력](../json/)의 `errors` 키와 같은 사실을 알려 주며, 분석기가 실패했거나 건너뛴 파일이 있으면 `false`가 됩니다. 파일 경로는 `%SRCROOT%` 기준 상대 경로이고, `originalUriBaseIds`가 이 값을 Noir를 실행한 디렉터리로 지정합니다.

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
                  "uri": "src/routes.cr",
                  "uriBaseId": "%SRCROOT%"
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
                  "uri": "src/routes.cr",
                  "uriBaseId": "%SRCROOT%"
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
      ],
      "originalUriBaseIds": {
        "%SRCROOT%": {
          "uri": "file:///path/to/project/"
        }
      }
    }
  ]
}
```

## SARIF 기능

### 엔드포인트 발견

각 엔드포인트는 아래 정보와 함께 SARIF result로 보고됩니다.

*   Rule ID: `endpoint-discovery`
*   Level: `note` (정보성)
*   Message: HTTP 메서드, URL 경로, 파라미터
*   Location: 엔드포인트가 정의된 파일 경로와 줄 번호

### 패시브 스캔 통합

패시브 스캔(`-P` 또는 `--passive-scan`)을 함께 쓰면 보안 발견 사항도 SARIF에 들어갑니다. 레벨은 심각도에 따라 정해집니다.

*   critical, high → `error`
*   medium → `warning`
*   low → `note`
*   그 밖의 심각도 → `none`

`-P`는 기본적으로 high와 critical 결과만 남깁니다. 나머지도 보려면 `--passive-scan-severity medium`(또는 `low`)으로 기준을 낮추세요.

각 패시브 스캔 규칙은 이름, 설명과 함께 `rules` 배열에 들어가고, 첫 번째 참조 링크는 `helpUri`가 됩니다. 발견 사항의 메시지는 규칙 이름일 뿐 매칭된 텍스트가 아니므로, 탐지된 시크릿이 code scanning 알림에 그대로 노출되지 않습니다.

### Callee와 AI 컨텍스트

엔드포인트에 callee(`--include callee`)나 AI 리뷰 컨텍스트(`--ai-context`)가 있으면, 각 엔드포인트 result의 `properties.noir.callees`와 `properties.noir.ai_context`에 들어갑니다.

### Diff 모드

`--diff-path`나 `--diff-ref`와 함께 쓰면 `-f sarif`는 새로 생긴 공격 표면만 보고합니다. 규칙은 `diff-endpoint-added`, `diff-params-added`, `diff-auth-removed`입니다. 삭제된 라우트는 새 코드에 표시할 줄이 없어서 빠집니다. 자세한 내용은 [Diff](@/usage/more_features/diff/index.ko.md)를 참고하세요.

## 통합 예제

### GitHub Code Scanning

SARIF 결과를 [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)에 업로드하면 리포지토리 Security 탭에서 바로 확인할 수 있습니다.

```bash
# SARIF 출력 생성
noir scan . -f sarif -o noir-results.sarif --no-log

# GitHub CLI로 업로드 (API는 gzip 압축 후 base64로 인코딩한 파일을 받음)
gh api /repos/{owner}/{repo}/code-scanning/sarifs \
  -f sarif="$(gzip -c noir-results.sarif | base64 | tr -d '\n')" \
  -f ref=refs/heads/main \
  -f commit_sha="$(git rev-parse HEAD)"
```

### GitLab Security Dashboard

GitLab은 `sarif` 리포트 타입으로 SARIF를 읽습니다(GitLab Ultimate, 최신 버전). `sast` 리포트 타입은 GitLab 자체 JSON 스키마를 요구하므로 SARIF 파일을 넣으면 안 됩니다. `.gitlab-ci.yml`에 아래 잡을 추가하세요.

```yaml
noir_scan:
  script:
    - noir scan . -f sarif -o noir.sarif --no-log
  artifacts:
    reports:
      sarif: noir.sarif
```

### Azure DevOps

Azure Pipelines에서 SARIF 파일을 빌드 아티팩트로 게시하면 SARIF SAST Scans Tab 확장에서 결과를 볼 수 있습니다.

```yaml
- script: noir scan . -f sarif -o noir.sarif --no-log
  displayName: 'Run Noir Scan'

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: 'noir.sarif'
    ArtifactName: 'CodeAnalysisLogs'
```

## 추가 리소스

*   [SARIF 명세 v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
*   [GitHub Code Scanning 문서](https://docs.github.com/en/code-security/code-scanning)
*   [GitLab SARIF 리포트 문서](https://docs.gitlab.com/user/application_security/detect/sarif/)
*   [SARIF 튜토리얼](https://github.com/microsoft/sarif-tutorials)
