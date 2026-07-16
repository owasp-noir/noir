+++
title = "패시브 보안 스캔"
description = "트래픽을 보내지 않고 소스 코드에서 잠재적 보안 이슈를 잡아내는 룰 기반 점검."
weight = 5
sort_by = "weight"

+++

미리 정의된 룰로 코드의 잠재적 보안 문제를 찾습니다. 실제 공격 트래픽은 보내지 않으며, 정규 표현식과 문자열 매칭으로 흔한 보안 위험을 식별합니다.

## 사용법

패시브 스캔 실행:

```bash
noir scan <BASE_PATH> -P
```

사용자 정의 룰 사용:

```bash
noir scan <BASE_PATH> --passive-scan --passive-scan-path /path/to/your/rules.yml
```

### 심각도 필터링

`--passive-scan-severity`로 표시할 심각도 기준을 지정합니다:

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
  └── file: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr:4
```

**출력 구성:**
*   `[critical][hahwul-test][secret]`: 심각도, 룰 이름, 이슈 유형
*   `extract`: 매칭된 코드 라인
*   `file`: 파일 경로와 줄 번호
