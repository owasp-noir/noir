+++
title = "기본 패시브 스캔 규칙"
description = "기본 패시브 스캔 규칙 위치, 자동 업데이트 동작, 사용자 정의 방법."
weight = 2
sort_by = "weight"

+++

Noir는 일반적인 보안 취약점 탐지를 위한 기본 규칙을 제공합니다. 패시브 스캔 활성화(`-P`) 시 첫 실행에서 규칙을 자동 초기화하고, 업데이트를 확인하며, 선택적으로 자동 업데이트합니다.

## 규칙 위치

| OS      | 경로                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

## 자동 초기화 및 업데이트 확인

`-P` 활성화 시 Noir는:
1. 첫 실행 시 [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) 저장소를 `~/.config/noir/passive_rules/`로 클론
2. 로컬과 원격 저장소를 비교하여 업데이트 확인
3. 규칙이 오래된 경우 알림
4. 설정 시 자동 업데이트 수행

저장소: https://github.com/owasp-noir/noir-passive-rules

## CLI 옵션

- `--passive-scan-auto-update` — 시작 시 규칙 자동 업데이트
- `--passive-scan-no-update-check` — 업데이트 확인 건너뜀 (에어갭 환경에 유용)

두 옵션은 `~/.config/noir/config.yaml`에서도 설정할 수 있습니다.

## 사용 예시

```bash
# 기본 동작 - 업데이트를 확인하고 뒤쳐진 경우 알림
noir -b /app -P

# 시작 시 규칙을 자동 업데이트
noir -b /app -P --passive-scan-auto-update

# 업데이트 확인을 완전히 건너뜀
noir -b /app -P --passive-scan-no-update-check
```

## 예시 출력

첫 실행(자동 초기화):
```
⚬ Passive scanner enabled.
⚬ Initializing passive rules directory...
✔ Passive rules initialized successfully.
  ├── Using default passive rules.
  └── Loaded 15 valid passive scan rules.
```

업데이트가 가능한 경우:
```
⚬ Passive scanner enabled.
❏ Checking for passive rules updates...
▲ Passive rules are 3 commits behind the latest version.
  ├── Run 'git pull' in ~/.config/noir/passive_rules/ to update
  ├── Or use 'git clone https://github.com/owasp-noir/noir-passive-rules.git ~/.config/noir/passive_rules/' to get the latest rules
  ├── Or run 'noir -b . -P --passive-scan-auto-update' to auto-update on startup
```

자동 업데이트 활성화 시:
```
⚬ Passive scanner enabled.
❏ Checking for passive rules updates...
⚬ Updating passive rules (3 commits behind)...
✔ Passive rules updated successfully.
```

## 규칙 사용자 정의

같은 디렉터리에 `.yml` 또는 `.yaml` 규칙 파일을 추가하면 다음 패시브 스캔 시 자동으로 로드됩니다. 기본 규칙 세트를 수정할 필요가 없습니다.
