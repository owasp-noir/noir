+++
title = "GitHub Action"
description = "GitHub Actions에서 OWASP Noir로 엔드포인트를 찾고 패시브 보안 스캔을 돌립니다."
weight = 6
sort_by = "weight"

+++

CI에서 GitHub Actions로 OWASP Noir를 돌려 엔드포인트를 찾고, 원하면 패시브 보안 스캔도 함께 돌릴 수 있습니다.

## 빠른 시작

최소 워크플로:

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

- `base_path`: 분석 대상 디렉터리 (`-b/--base-path`)
- `endpoints`: 뒤 스텝에서 처리할 JSON 결과

## 입력값(Inputs)

| 이름 | 설명 | 필수 | 기본값 |
|---|---|---|---|
| `base_path` | 분석할 기준 경로 (`-b/--base-path`) | 예 | `.` |
| `url` | 엔드포인트의 기준 URL (`-u/--url`) | 아니오 | `` |
| `format` | 출력 형식 (`plain`, `yaml`, `json`, `jsonl`, `markdown-table`, `curl`, `httpie`, `oas2`, `oas3` 등) | 아니오 | `json` |
| `output_file` | 결과를 파일로 저장 (`-o/--output`) | 아니오 | `` |
| `techs` | 추가할 기술 지정 (`-t/--techs`) | 아니오 | `` |
| `exclude_techs` | 제외할 기술 지정 (`--exclude-techs`) | 아니오 | `` |
| `passive_scan` | 패시브 보안 스캔 켜기 (`-P/--passive-scan`) | 아니오 | `false` |
| `passive_scan_severity` | 패시브 스캔 최소 심각도 (`critical`, `high`, `medium`, `low`) | 아니오 | `high` |
| `use_all_taggers` | 모든 태거 활성화 (`-T/--use-all-taggers`) | 아니오 | `false` |
| `use_taggers` | 특정 태거만 활성화 (`--use-taggers`) | 아니오 | `` |
| `include_path` | `plain` 출력에 소스 파일 경로 추가. JSON에는 항상 들어 있음 (`--include-path`) | 아니오 | `false` |
| `verbose` | 상세 출력 (`--verbose`) | 아니오 | `false` |
| `debug` | 디버그 출력 (`-d/--debug`) | 아니오 | `false` |
| `concurrency` | 동시성 수준 (`--concurrency`) | 아니오 | `` |
| `exclude_codes` | 제외할 HTTP 상태 코드, 쉼표로 구분 (`--exclude-codes`) | 아니오 | `` |
| `status_codes` | 발견한 엔드포인트의 HTTP 상태 코드 표시 (`--status-codes`) | 아니오 | `false` |
| `ai_provider` | AI 제공업체 접두사 또는 전체 커스텀 URL (`--ai-provider`) | 아니오 | `` |
| `ai_model` | AI 모델명 (`--ai-model`) | 아니오 | `` |
| `ai_key` | AI API 키 (`--ai-key`) | 아니오 | `` |
| `ai_agent` | 에이전트형 AI 워크플로 켜기 (`--ai-agent`) | 아니오 | `false` |
| `probe` | 발견한 엔드포인트로 HTTP 요청 보내기 (`--probe`) | 아니오 | `false` |
| `probe_via` | 프로브 요청을 이 프록시 URL로 보내기 (`--probe-via`) | 아니오 | `` |
| `export_es` | Elasticsearch 또는 OpenSearch에 엔드포인트 색인 (`--export-es`) | 아니오 | `` |
| `export_webhook` | 엔드포인트 목록을 JSON으로 웹훅 URL에 POST (`--export-webhook`) | 아니오 | `` |
| `diff_path` | diff 분석에 쓸 이전 버전 코드 경로 (`--diff-path`) | 아니오 | `` |
| `diff_ref` | 체크아웃과 비교할 git 리비전(예: pull request의 base). 체크아웃에 없으면 가져옴 (`--diff-ref`) | 아니오 | `` |
| `fail_on` | diff에 `added`, `removed`, `changed`, `auth-removed` 중 하나라도 있으면 스텝 실패(종료 코드 `3`) (`--fail-on`) | 아니오 | `` |
| `no_log` | 실행 로그를 숨기고 결과만 표시 (`--no-log`) | 아니오 | `true` |

**참고:**
- 불리언 옵션은 문자열(`'true'`/`'false'`)로 넘기세요.
- `output_file`은 워크스페이스 기준 경로입니다. 뒤 스텝에서 리포트 파일이 필요하면 지정하세요. 스텝 출력값은 지정 여부와 관계없이 채워집니다.
- `status_codes`, `exclude_codes`, `probe`, `probe_via`는 `url`이 있어야 합니다. 없으면 스캔이 에러로 멈춥니다.
- `jsonl`이면 아래 출력값은 각 줄을 모아 `json`과 같은 문서 하나로 만듭니다.

## 출력값(Outputs)

| 이름 | 설명 |
|---|---|
| `endpoints` | `format`이 `json`이나 `jsonl`일 때 Noir 결과 문서 전체(`{"endpoints":[...],"passive_results":[...],"errors":[...]}`). 다른 출력 형식이면 빈 값 |
| `passive_results` | `format`이 `json`이나 `jsonl`일 때 패시브 스캔 결과 JSON 배열. 패시브 스캔을 껐거나, 결과가 없거나, 다른 출력 형식이면 `[]` |

출력값 활용:

~~~yaml
- name: Count endpoints
  run: echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

- name: Show passive issues (if enabled)
  run: echo '${{ steps.noir.outputs.passive_results }}' | jq '. | length'
~~~

## 예시

### 고급 스캔

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

### 모노레포 매트릭스

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

### Pull Request 공격 표면 리뷰

풀 리퀘스트를 기준 브랜치와 비교해 결과를 코멘트로 남기고, 인증이 빠진 라우트가 생기면 체크를 실패시킵니다.

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

`actions/checkout`은 기본으로 커밋 하나만 가져옵니다. `diff_ref`가 체크아웃에 없으면 Action이 스캔 전에 그 리비전을 가져옵니다. diff가 `fail_on`에 걸리면 스텝은 종료 코드 `3`으로 실패하지만 리포트 파일은 그대로 쓰이므로, 위 코멘트 스텝은 `if: always()`로 실행됩니다. 코멘트 대신 코드 줄에 바로 표시하려면 `format: 'sarif'`로 출력하고 `github/codeql-action/upload-sarif`로 업로드하세요.

### 프레임워크별 스캔

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

### 상태 코드 설정

상태 코드는 실제 요청으로 얻으므로 `url`이 실행 중인 앱을 가리켜야 합니다.

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    url: 'http://localhost:3000'
    status_codes: 'true'       # HTTP 상태 코드 포함
    exclude_codes: '404,429'   # 노이즈가 많은 코드 제외
~~~

### 다른 출력 형식

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    format: 'markdown-table'   # 또는: 'curl', 'httpie', 'yaml', 'jsonl', 'oas3'
    output_file: 'noir.md'
~~~

## 모범 사례

1. `passive_scan: 'true'`로 보안 문제를 일찍 잡으세요.
2. `passive_scan_severity`와 `exclude_codes`로 노이즈를 줄이세요.
3. JSON 출력에는 엔드포인트마다 소스 파일 위치가 이미 들어 있습니다. `plain` 출력에서 보려면 `include_path: 'true'`를 켜세요.
4. 자동 탐지가 놓친 프레임워크는 `techs`로 추가하고, 필요 없는 분석기는 `exclude_techs`로 빼세요.
5. `actions/upload-artifact`로 결과를 보관하세요.

## 트러블슈팅

**엔드포인트가 나오지 않을 때:**
- `base_path`가 소스 디렉터리를 가리키는지 확인
- 저장소가 지원하는 프레임워크를 쓰는지 확인
- `techs`를 직접 지정

**출력이 크거나 느린 경우:**
- `format: 'jsonl'`로 `output_file`에 저장 (한 줄에 엔드포인트 하나)
- `base_path` 범위를 줄이거나 `techs`/`exclude_techs`로 거르기

**진단이 어려운 경우:**
- `debug: 'true'`나 `verbose: 'true'`를 켜고 `no_log: 'false'`도 함께 지정. `no_log`는 기본값이 `true`라 로그를 숨깁니다

**HTTP 상태 코드 노이즈:**
- `status_codes: 'false'`로 비활성화 또는 `exclude_codes`로 제외

## 구현 참고 사항

- Action은 `ghcr.io/owasp-noir/noir` Docker 이미지로 실행됩니다. 이미지 태그는 고정한 ref를 따릅니다. `@v1.4.0`은 `1.4.0`, `@main`은 `main`, 커밋 SHA는 `latest`를 씁니다. 태그를 받을 수 없으면(예: 이미지가 없는 브랜치) 경고를 남기고 `latest`로 대신 실행합니다.
- 입력값 하나가 CLI 플래그 하나에 대응합니다.
- 지원 기술 목록: `noir list techs`
