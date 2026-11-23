+++
title = "접근 매트릭스"
description = "소스에서 찾은 가드를 읽어, 각 엔드포인트에 어떤 호출자가 접근할 수 있는지 마크다운 표로 보여줍니다."
weight = 5
sort_by = "weight"

+++

`-f access-matrix`는 엔드포인트마다 한 행, 호출자 종류마다 한 열인 마크다운 표를 출력합니다. 각 칸은 그 호출자가 Noir가 경로에서 찾은 가드를 통과하는지 나타냅니다.

## 사용법

```bash
noir scan . -f access-matrix --no-log
```

매트릭스는 태그로 만들기 때문에, `-T`나 `--use-taggers`로 태거를 직접 고르지 않으면 이 형식은 모든 태거를 실행합니다. 로그에는 `Running all taggers (implied by -f access-matrix).`가 출력됩니다.

## 출력 예제

```
| Endpoint | `anonymous` | `authenticated` | `role:ADMIN` | `role:MANAGER` | `role:USER` | Requires |
| --- | --- | --- | --- | --- | --- | --- |
| `DELETE /api/admin/users/{id}` | - | - | Y | - | - | `role:ADMIN` |
| `POST /api/posts` | - | - | - | - | Y | `role:USER & authenticated` |
| `DELETE /api/posts/{id}` | - | - | Y | Y | - | `(role:ADMIN \| role:MANAGER) & authenticated` |
| `GET /posts/:id` | - | ? | ? | ? | ? | `authenticated & unresolved` |
| `GET /api/public/health` | Y | Y | Y | Y | Y | no guard found |

Y allowed, - denied, ? unknown (a guard noir could not read)
```

## 열

| 열 | 의미 |
|---|---|
| `anonymous` | 로그인하지 않은 호출자입니다. |
| `authenticated` | 역할, 권한, 스코프 없이 로그인한 호출자입니다. |
| `role:X`, `permission:X`, `scope:X` | 그 값 하나만 가진 로그인한 호출자입니다. 스캔에서 어떤 엔드포인트가 요구하는 값마다 열이 하나씩 생깁니다. |
| Requires | Noir가 읽은 요구 조건입니다. 아래에서 설명합니다. |

## 칸

| 표시 | 의미 |
|---|---|
| `Y` | 호출자가 Noir가 찾은 모든 가드를 통과합니다. |
| `-` | 가드 하나 이상이 호출자를 거부합니다. |
| `?` | 호출자를 거부하는 가드는 없지만 `unresolved` 가드가 있어 Noir가 판단할 수 없습니다. |

`-`가 `?`보다 우선합니다. 가드 하나가 호출자를 거부하면, 다른 가드를 알 수 없어도 칸은 `-`입니다.

## Requires 열

요구 조건은 모두 만족해야 하는 조건의 목록이며 `&`로 이어집니다. 괄호 안의 조건은 그중 하나만 만족하면 되며 `|`로 이어집니다.

- `unresolved`는 Noir가 찾았지만 읽지 못한 가드입니다. 빈(bean) 메서드 호출, 다른 파일의 상수, 사용자 정의 가드 클래스가 그 예입니다. JSON 출력은 각 가드의 소스 텍스트를 태그의 `requires` 필드에 남깁니다.
- `deny`는 Spring `denyAll()`처럼 모든 호출자를 거부하는 가드입니다. 그 행의 모든 칸은 `-`입니다.
- `no guard found`는 Noir가 경로에서 가드를 찾지 못했다는 뜻입니다. 경로가 공개로 선언되었다는 뜻은 아닙니다. 소스가 익명 호출자에게 열어 둔 경로(예: Noir가 `anonymous` 태그를 붙인 Quarkus `@PermitAll` 메서드)는 여기에 `anonymous`로 표시됩니다.

## 요구 조건의 출처

Noir는 엔드포인트의 태그에서 요구 조건을 읽습니다.

- `requires` 필드가 있는 태그([JSON 출력](../json/) 참고)는 적힌 조건을 그대로 씁니다. 현재는 `spring_auth` 태거가 이 필드를 채웁니다.
- 다른 태거가 붙인 `auth` 태그는 `authenticated & unresolved`로 읽습니다. 태그는 가드가 있다는 것만 알려 주고, 무엇을 검사하는지는 알려 주지 않습니다.
- 다른 태거가 붙인 `authz` 태그는 `unresolved`로 읽습니다.
- `anonymous` 태그는 엔드포인트의 다른 모든 가드 태그보다 우선하며, 그 행은 `anonymous`로 표시됩니다.

엔드포인트의 모든 태그에서 나온 조건은 모두 만족해야 합니다. 표에는 `-f markdown-table`이 포함하는 모든 엔드포인트가 들어가며, 외부로 나가는 클라이언트 호출이나 HTTP가 아닌 경로를 걸러 내지 않습니다.
