+++
title = "Diff 모드로 코드 비교하기"
description = "코드베이스의 두 버전을 비교하여 엔드포인트 변경사항을 식별합니다."
weight = 2
sort_by = "weight"

+++

코드베이스의 두 버전을 비교하여 엔드포인트 변경사항을 식별합니다. 코드 리뷰, 보안 평가, 기능 영향 분석에 유용합니다.

```bash
noir scan <NEW_VERSION_PATH> --diff-path <OLD_VERSION_PATH>
```

## 출력

### 일반 텍스트 출력

기본 출력에서는 변경사항을 **Added**(새 엔드포인트), **Removed**(삭제된 엔드포인트), **Changed**(두 버전 모두에 존재하지만 파라미터 등 세부 정보가 달라진 엔드포인트) 섹션으로 묶어 보여줍니다. 엔드포인트는 URL과 메서드 조합으로 매칭되므로, 메서드가 바뀐 경우에는 Changed가 아니라 Added 하나와 Removed 하나로 나타납니다. 각 섹션은 표준 일반 텍스트 형식으로 렌더링됩니다.

```
───────────── ✚ Added (2) ─────────────

GET /
  ○ headers: 
    └── x-api-key

POST /update

──────────── ✖ Removed (1) ─────────────

GET /secret.html
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
