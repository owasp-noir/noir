+++
title = "Diff 모드로 코드 비교하기"
description = "코드베이스의 두 버전을 비교하여 엔드포인트 변경사항을 식별합니다."
weight = 2
sort_by = "weight"

+++

코드베이스의 두 버전을 비교하여 엔드포인트 변경사항을 식별합니다. 코드 리뷰, 보안 평가, 기능 영향 분석에 유용합니다.

```bash
noir -b <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## 출력

### 일반 텍스트 출력

기본 출력에서는 각 변경사항을 **Added**(새 엔드포인트), **Removed**(삭제된 엔드포인트), **Changed**(파라미터나 메서드가 변경된 엔드포인트)로 표시합니다.

```
[*] ============== DIFF ==============
[I] Added: / GET
[I] Added: /update POST
[I] Removed: /secret.html GET
[I] Removed: /posts GET
```

### JSON 및 YAML 출력

`-f json` 또는 `-f yaml`을 사용하면 구조화된 출력을 얻을 수 있습니다. 결과는 세 가지 카테고리로 분류됩니다.

```json
{
  "added": [...],
  "removed": [...],
  "changed": [...]
}
```

CI/CD에서 활용하면 `added`와 `changed` 엔드포인트만 DAST 스캐너에 넘겨서, 변경된 공격 표면에 집중할 수 있습니다.
