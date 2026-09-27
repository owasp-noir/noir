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

## git 리비전과 비교하기

git 저장소 안이라면 이전 버전을 따로 체크아웃할 필요가 없습니다. `--diff-ref`에 git이 이해하는 리비전(브랜치, 태그, 커밋, `HEAD~1` 등)을 넘기면 그 시점을 이전 버전으로 삼습니다.

```bash
# 이 브랜치가 main 대비 공격 표면을 얼마나 늘렸는지 확인
noir scan . --diff-ref main

# 모노레포에서 서비스 하나만 비교
noir scan ./services/billing --diff-ref origin/main -f json
```

Noir는 스캔 경로 아래에서 REF가 추적하던 파일을 임시 디렉터리에 풀어 이전 버전으로 스캔하고, 스캔이 끝나면 그 디렉터리를 지웁니다. HEAD, 인덱스, 작업 트리는 건드리지 않고 git 훅도 실행하지 않습니다. 삭제된 엔드포인트의 코드 경로는 임시 디렉터리가 아니라 사용자가 넘긴 경로 기준으로 표시됩니다.

알아둘 점:

- 새 버전은 작업 트리를 그대로 스캔하므로 추적되지 않은 파일도 포함됩니다. 이전 버전에는 REF 시점에 git이 추적하던 파일만 들어갑니다.
- 모든 base 경로는 같은 저장소 안에 있어야 합니다. `--diff-ref`와 `--diff-path`는 함께 쓸 수 없습니다.
- REF 시점에 없던 base 경로는 빈 디렉터리로 스캔되므로, 그 아래 엔드포인트는 모두 Added로 나옵니다.
- CI 체크아웃은 대개 얕은 클론입니다(`actions/checkout`은 기본으로 커밋 하나만 가져옵니다). `fetch-depth: 0` 등으로 리비전을 먼저 가져오지 않으면 Noir가 그 이유를 담은 오류를 내고 멈춥니다.

## 출력

### 일반 텍스트 출력

기본 출력에서는 변경사항을 **Added**(새 엔드포인트), **Removed**(삭제된 엔드포인트), **Changed**(두 버전 모두에 존재하지만 파라미터나 태그가 달라진 엔드포인트) 섹션으로 묶어 보여줍니다. 엔드포인트는 URL과 메서드 조합으로 매칭되므로, 메서드가 바뀐 경우에는 Changed가 아니라 Added 하나와 Removed 하나로 나타납니다. 각 섹션은 표준 일반 텍스트 형식으로 렌더링되고, Changed 엔드포인트 아래에는 무엇이 바뀌었는지가 표시됩니다.

```
───────────── ✚ Added (2) ─────────────

GET /
  ○ headers: 
    └── x-api-key

POST /update

──────────── ✖ Removed (1) ─────────────

GET /secret.html

──────────── ≠ Changed (2) ─────────────

GET /public?q=
  + query: q

GET /profile
  ! auth tag removed
```

### 무엇을 변경으로 보는가

- **파라미터**는 이름과 전달 위치(query, header, cookie, path, form, JSON 본문)로 비교합니다. 예시 값이나 기본값만 바뀐 파라미터는 클라이언트가 보내는 요청이 달라지지 않으므로 변경으로 보지 않습니다.
- **태그**는 이름으로 비교합니다. 태그는 태거가 붙이므로 `-T`(또는 `--use-taggers`)와 함께 실행해야 보입니다.
- **`auth` 제거**: 이전에는 `auth` 태그가 있었는데 지금은 없는 엔드포인트는 맨 위에 `! auth tag removed`로 표시됩니다. 로그인이 필요하던 라우트가 더 이상 요구하지 않는다는 뜻이라 리뷰에서 가장 먼저 봐야 할 변경입니다. auth 태거는 `-T`나 `--use-taggers`를 줄 때만 실행되므로, 이 줄을 보려면 둘 중 하나를 켜세요.

### JSON 및 YAML 출력

`-f json` 또는 `-f yaml`을 사용하면 구조화된 출력을 얻을 수 있습니다. 결과는 세 가지 카테고리로 분류됩니다.

```json
{
  "added": [...],
  "removed": [...],
  "changed": [...],
  "changes": [
    {
      "method": "GET",
      "url": "/profile",
      "params_added": [],
      "params_removed": [{ "name": "token", "param_type": "header" }],
      "tags_added": [],
      "tags_removed": ["auth"],
      "auth_removed": true
    }
  ]
}
```

`changed`에는 현재 시점의 엔드포인트가 들어갑니다. `changes`에는 `changed`의 각 항목과 같은 순서로, 무엇이 달라졌는지를 담은 레코드가 하나씩 들어갑니다.

### Markdown 및 SARIF 출력

`-f markdown-table`은 diff를 pull request 코멘트 형태로 보여줍니다. 개수 요약 표, 인증이 빠진 라우트, 그리고 추가/삭제/변경된 엔드포인트 표가 차례로 나옵니다.

`-f sarif`는 코드 스캐닝용으로 새로 생긴 공격 표면을 보고합니다. 추가된 엔드포인트와 새 파라미터는 note, 인증이 빠진 라우트는 warning입니다. 삭제된 엔드포인트는 리뷰 대상 코드에 가리킬 줄이 없어서 제외합니다. 다른 포맷에는 그대로 나옵니다.

TOML 출력도 지원합니다. 그 밖의 `-f`는 경고와 함께 텍스트 diff로 출력됩니다.

## Diff 결과로 CI 실패시키기

`--fail-on`을 주면 리포트를 쓴 뒤, diff에 지정한 종류가 하나라도 있을 때 종료 코드 `3`으로 끝납니다.

```bash
noir scan . --diff-ref origin/main --fail-on auth-removed,added -f markdown-table -o diff.md
```

| 종류 | 조건 |
|---|---|
| `added` | 이전에는 없던 엔드포인트가 생김 |
| `removed` | 이전에 있던 엔드포인트가 사라짐 |
| `changed` | 양쪽에 모두 있는 엔드포인트의 파라미터나 태그가 달라짐 |
| `auth-removed` | `auth` 태그가 있던 엔드포인트에서 태그가 사라짐 |

`auth-removed`는 auth 태거 결과에 의존하므로, `-T`나 `--use-taggers`를 주지 않았다면 모든 태거를 자동으로 켭니다. 실패 사유는 `--no-log`여도 stderr로 출력됩니다. 종료 코드 `1`은 여전히 사용법 오류, `2`는 `--strict`의 불완전 스캔이며 `2`가 `3`보다 우선합니다.

같은 검사를 로컬의 git `pre-push` 훅에서도 쓸 수 있습니다.

```bash
#!/bin/sh
exec noir scan . --diff-ref origin/main --fail-on auth-removed --no-log
```

pull request 워크플로 전체 예시는 [GitHub Action](../../github_action/)을 참고하세요.

CI/CD에서 활용하면 `added`와 `changed` 엔드포인트만 DAST 스캐너에 넘겨서, 변경된 공격 표면에 집중할 수 있습니다.
