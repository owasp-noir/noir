+++
title = "패시브 보안 스캔"
description = "트래픽을 보내지 않고 소스 코드에서 잠재적 보안 이슈를 잡아내는 규칙 기반 점검."
weight = 5
sort_by = "weight"

+++

패시브 스캔은 소스 코드를 YAML 규칙과 대조해, 보안 문제로 보이는 줄(하드코딩된 시크릿, 위험한 호출)을 보고합니다. 트래픽은 보내지 않습니다. 규칙은 문자열과 정규 표현식으로 매칭합니다.

## 사용법

패시브 스캔 실행:

```bash
noir scan <BASE_PATH> -P
```

직접 만든 규칙을 쓰려면 `--passive-scan-path`를 주세요. 파일 하나가 아니라 **디렉터리**를 받으며, 그 아래의 모든 `*.yml` / `*.yaml`을 읽습니다. 이 실행에서는 기본 규칙을 내려받지도, 쓰지도 않으므로 git도 네트워크도 필요 없습니다. 이 플래그는 여러 번 쓸 수 있고, 두 디렉터리에서 같은 규칙 id가 들어오면 한 번만 로드합니다.

```bash
noir scan <BASE_PATH> -P --passive-scan-path /path/to/your/rules/
```

### 심각도 필터링

`--passive-scan-severity`로 보고할 최소 심각도를 정합니다:

- `critical`: critical만
- `high`: high와 critical (기본값)
- `medium`: medium 이상
- `low`: 전체

예시:

```bash
# critical만
noir scan <BASE_PATH> -P --passive-scan-severity critical

# medium 이상
noir scan <BASE_PATH> -P --passive-scan-severity medium

# 전체
noir scan <BASE_PATH> -P --passive-scan-severity low
```

## 출력 형식

예시 출력:

```
★ Passive Results:
[critical][hahwul-test][secret] use x-api-key
  ├── extract:   env.request.headers["x-api-key"].as(String)
  └── file: spec/functional_test/fixtures/crystal/kemal/src/testapp.cr:4
```

**출력 구성:**
*   `[critical][hahwul-test][secret]`: 심각도, 규칙 `id`, 규칙 `category`
*   `use x-api-key`: 규칙 이름(`info.name`)
*   `extract`: 매칭된 코드 라인
*   `file`: 파일 경로와 줄 번호
