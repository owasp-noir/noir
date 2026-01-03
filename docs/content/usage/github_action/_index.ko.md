+++
title = "GitHub Action"
description = "GitHub Actions 워크플로우에서 OWASP Noir를 실행해 엔드포인트 탐지와 수동(패시브) 보안 점검을 수행하는 방법을 안내합니다."
weight = 6
sort_by = "weight"

[extra]
+++

OWASP Noir는 CI에서 코드베이스의 공격 표면을 분석하기 위한 GitHub Action을 제공합니다. 다양한 언어와 프레임워크 전반에서 엔드포인트를 탐지하고, 선택적으로 수동(패시브) 보안 점검을 수행합니다.

이 문서는 워크플로우에 Noir를 추가하고, 입력값을 구성하며, 출력값을 활용하고, 자주 발생하는 문제를 해결하는 방법을 설명합니다.

## 빠른 시작

푸시/PR 시 최소 구성을 실행하는 예시:

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

- `base_path`는 분석 대상 디렉터리입니다(커맨드라인의 `-b/--base-path`와 동일).
- `endpoints` 출력에는 JSON 결과가 담기며, `jq` 등으로 후처리할 수 있습니다.

## 입력값(Inputs)

| 이름 | 설명 | 필수 | 기본값 |
|---|---|---|---|
| `base_path` | 분석할 기준 경로 (`-b/--base-path`) | 예 | `.` |
| `url` | 엔드포인트의 기준 URL (`-u/--url`) | 아니오 | `` |
| `format` | 출력 형식 (`plain`, `yaml`, `json`, `jsonl`, `markdown-table`, `curl`, `httpie`, `oas2`, `oas3` 등) | 아니오 | `json` |
| `output_file` | 결과를 파일로 저장 (`-o/--output`) | 아니오 | `` |
| `techs` | 포함할 기술 스택 지정 (`-t/--techs`) | 아니오 | `` |
| `exclude_techs` | 제외할 기술 스택 지정 (`--exclude-techs`) | 아니오 | `` |
| `passive_scan` | 수동(패시브) 보안 점검 활성화 (`-P/--passive-scan`) | 아니오 | `false` |
| `passive_scan_severity` | 수동 점검 최소 심각도 (`critical`, `high`, `medium`, `low`) | 아니오 | `high` |
| `use_all_taggers` | 모든 태거 활성화(광범위 분석) (`-T/--use-all-taggers`) | 아니오 | `false` |
| `use_taggers` | 특정 태거만 활성화 (`--use-taggers`) | 아니오 | `` |
| `include_path` | 결과에 소스 파일 경로 포함 (`--include-path`) | 아니오 | `false` |
| `verbose` | 상세 출력 (`--verbose`) | 아니오 | `false` |
| `debug` | 디버그 출력 (`-d/--debug`) | 아니오 | `false` |
| `concurrency` | 동시성 수준 (`--concurrency`) | 아니오 | `` |
| `exclude_codes` | 제외할 HTTP 상태코드(쉼표 구분) (`--exclude-codes`) | 아니오 | `` |
| `status_codes` | 발견된 엔드포인트에 HTTP 상태코드 표시 (`--status-codes`) | 아니오 | `false` |

참고:
- YAML의 타입 변환 이슈를 피하려면 불리언은 문자열(`'true'`/`'false'`)로 전달하세요.
- `output_file`을 지정하면 출력값 제공과 함께 해당 파일에도 결과가 저장됩니다.

## 출력값(Outputs)

| 이름 | 설명 |
|---|---|
| `endpoints` | 엔드포인트 분석 결과(JSON) |
| `passive_results` | 수동(패시브) 점검 결과(JSON, `passive_scan` 활성화 시 제공) |

출력값 활용 예시:

~~~yaml
- name: Count endpoints
  run: echo '${{ steps.noir.outputs.endpoints }}' | jq '.endpoints | length'

- name: Show passive issues (if enabled)
  run: echo '${{ steps.noir.outputs.passive_results }}' | jq '. | length'
~~~

## 예시

### 수동 점검 및 아티팩트 저장을 포함한 고급 스캔

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

### 모노레포/매트릭스 예시

여러 서비스를 병렬로 분석:

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

### 프레임워크별 스캔

자동 감지가 충분하지 않을 때는 기술 스택을 명시적으로 지정하세요:

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

### 상태코드 부가 정보 및 제외 설정

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    status_codes: 'true'       # HTTP 상태코드 포함
    exclude_codes: '404,429'   # 소음이 많은 코드 제외
~~~

### 리포팅을 위한 대체 포맷

마크다운 표 또는 cURL 명령을 생성:

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    format: 'markdown-table'   # 또는: 'curl', 'httpie', 'yaml', 'jsonl', 'oas3'
    output_file: 'noir.md'
~~~

## 모범 사례

1. 수동 점검(`passive_scan: 'true'`)을 활성화하여 보안 스멜을 조기에 확인하세요.
2. `passive_scan_severity`와 `exclude_codes`로 노이즈를 조절하세요.
3. `include_path: 'true'`로 파일 경로를 포함해 트라이애지와 코드 탐색을 빠르게 하세요.
4. 자동 감지가 부족하면 `techs`로 기술 스택을 고정하고, 불필요한 분석은 `exclude_techs`로 배제하세요.
5. `actions/upload-artifact`로 결과를 보존하거나, PR 코멘트/상태로 게시해 협업을 촉진하세요.

## 트러블슈팅

- 엔드포인트가 발견되지 않음
  - `base_path`가 실제 소스 디렉터리를 가리키는지 확인하세요(예: 루트가 아닌 `src/`).
  - 지원되는 언어/프레임워크가 포함되어 있는지 확인하세요.
  - `techs`를 명시적으로 지정해 보세요(예: `rails`, `express`, `django`).

- 출력이 너무 크거나 처리에 시간이 걸림
  - 라인 단위 처리를 위해 `format: 'jsonl'`을 사용하세요.
  - `base_path` 범위를 축소하거나 `techs`/`exclude_techs`로 필터링하세요.

- 동작을 진단하기 어려움
  - `debug: 'true'` 및 `verbose: 'true'`를 켜서 상세 로그를 확인하세요.
  - `include_path: 'true'`로 파일 경로를 포함해 추적 가능성을 높이세요.

- HTTP 상태코드로 인한 노이즈
  - `status_codes: 'false'`로 비활성화하거나 `exclude_codes`로 소음이 많은 코드를 제외하세요.

## 구현 참고 사항

- 이 액션은 Docker 컨테이너에서 실행되므로 GitHub 호스티드 러너 전반에서 일관되게 동작합니다.
- 입력값은 Noir CLI 플래그와 직접 1:1로 매핑됩니다. 로컬에서 사용하던 CLI 옵션을 동일하게 설정하면 쉽게 전환할 수 있습니다.

지원되는 전체 기술 목록은 로컬에서 `--list-techs` 옵션으로 확인하거나 프로젝트의 기술 목록 문서를 참고하세요.
