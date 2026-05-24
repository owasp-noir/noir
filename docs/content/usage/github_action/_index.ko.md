+++
title = "GitHub Action"
description = "GitHub Actions에서 OWASP Noir로 엔드포인트 탐지와 패시브 보안 점검을 수행합니다."
weight = 6
sort_by = "weight"

+++

GitHub Actions에서 OWASP Noir를 실행하여 엔드포인트 탐지와 패시브 보안 점검을 수행합니다.

## 빠른 시작

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
- `endpoints`: 후처리 가능한 JSON 출력

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

**참고:**
- 불리언 옵션은 문자열(`'true'`/`'false'`)로 전달
- `output_file` 지정 시 파일 저장과 출력값 모두 제공

## 출력값(Outputs)

| 이름 | 설명 |
|---|---|
| `endpoints` | 엔드포인트 분석 결과(JSON) |
| `passive_results` | 수동(패시브) 점검 결과(JSON, `passive_scan` 활성화 시 제공) |

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
name: Comprehensive Security Analysis
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
          include_path: 'true'
~~~

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

### 상태코드 설정

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    status_codes: 'true'       # HTTP 상태코드 포함
    exclude_codes: '404,429'   # 소음이 많은 코드 제외
~~~

### 대체 포맷

~~~yaml
- uses: owasp-noir/noir@main
  with:
    base_path: '.'
    format: 'markdown-table'   # 또는: 'curl', 'httpie', 'yaml', 'jsonl', 'oas3'
    output_file: 'noir.md'
~~~

## 모범 사례

1. `passive_scan: 'true'`로 보안 문제를 조기에 탐지
2. `passive_scan_severity`와 `exclude_codes`로 노이즈 조절
3. `include_path: 'true'`로 트리아지 및 코드 탐색 가속화
4. `techs`로 프레임워크를 지정하고, `exclude_techs`로 불필요한 분석 배제
5. `actions/upload-artifact`로 결과 보존

## 트러블슈팅

**엔드포인트 미발견:**
- `base_path`가 소스 디렉터리를 가리키는지 확인
- 지원되는 프레임워크가 포함되어 있는지 확인
- `techs`를 명시적으로 지정

**출력이 크거나 느린 경우:**
- `format: 'jsonl'`로 스트리밍 처리
- `base_path` 범위 축소 또는 `techs`/`exclude_techs`로 필터링

**진단이 어려운 경우:**
- `debug: 'true'` 및 `verbose: 'true'` 활성화
- `include_path: 'true'`로 추적성 확보

**HTTP 상태코드 노이즈:**
- `status_codes: 'false'`로 비활성화 또는 `exclude_codes`로 제외

## 구현 참고 사항

- Docker 컨테이너에서 실행되어 일관된 동작 보장
- 입력값은 CLI 플래그와 1:1 매핑
- 지원 기술 목록: `noir list techs`
