+++
title = "Diff 모드로 코드 비교하기"
description = "Noir의 diff 모드를 사용하여 코드베이스의 두 가지 버전을 비교하고 변경사항을 식별하는 방법을 알아보세요. 이는 코드 변경이 API에 미치는 영향을 이해하는 강력한 기능입니다."
weight = 2
sort_by = "weight"

+++

Diff 모드는 Noir의 강력한 기능으로 코드베이스의 두 버전을 비교하고 발견된 엔드포인트 측면에서 정확히 무엇이 변경되었는지 볼 수 있습니다. 이는 코드 리뷰, 보안 평가, 새로운 기능의 영향을 이해하는 데 매우 유용할 수 있습니다.

diff 모드를 사용하려면 `-b` 플래그로 베이스 경로(코드의 새 버전을 나타냄)를 제공하고 `--diff-path` 플래그로 비교 경로(코드의 이전 버전을 나타냄)를 제공합니다.

```bash
noir -b <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## 출력 이해하기

diff 모드의 출력은 두 버전 간에 추가, 제거 또는 변경된 엔드포인트를 보여줍니다.

### 일반 텍스트 출력

기본 일반 텍스트 출력에서는 변경사항의 간단한 요약을 얻습니다:

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
```

### JSON 및 YAML 출력

더 자세하고 기계가 읽을 수 있는 출력을 원한다면 JSON 또는 YAML 형식(`-f json` 또는 `-f yaml`)을 사용할 수 있습니다. 이는 전체 세부사항을 포함하여 추가, 제거 및 변경된 엔드포인트의 구조화된 보기를 제공합니다.

```json
{
  "added": [
    {
      "url": "/",
      "method": "GET",
      // ... 전체 엔드포인트 세부사항
    }
  ],
  "removed": [
    {
      "url": "/secret.html",
      "method": "GET",
      // ... 전체 엔드포인트 세부사항
    }
  ],
  "changed": []
}
```

diff 모드를 사용하면 더 효율적인 CI/CD 파이프라인을 구축할 수 있습니다. 예를 들어, DAST(Dynamic Application Security Testing) 도구를 구성하여 새 릴리스에서 추가되거나 수정된 엔드포인트만 스캔하도록 하여 시간과 자원을 절약할 수 있습니다.