+++
title = "기본 패시브 스캔 규칙"
description = "Noir가 기본 패시브 스캐닝 규칙을 저장하는 위치와 보안 분석을 향상시키기 위해 사용자 정의 규칙으로 확장할 수 있는 방법을 알아보세요."
weight = 2
sort_by = "weight"

[extra]
+++

Noir는 패시브 스캐닝 기능을 위한 기본 규칙 세트와 함께 제공됩니다. 이러한 규칙은 일반적인 보안 취약점을 탐지하기 위해 Noir 팀에서 큐레이션했습니다. 패시브 스캔을 활성화(`-P`)하면 첫 실행 시 규칙을 자동으로 초기화하고, 시작 시 업데이트를 확인하며, 로컬 규칙이 최신이 아니면 명확한 안내와 함께 알려주고, 옵션으로 자동 업데이트를 수행할 수 있습니다.

## 규칙 위치

기본 규칙은 운영 체제에 따라 특정 디렉토리에 저장됩니다:

| OS      | 경로                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

`-P` 또는 `--passive-scan` 플래그로 패시브 스캔을 실행하면 Noir는 이 디렉토리에서 규칙을 찾습니다.

## 자동 초기화 및 업데이트 확인

패시브 스캔이 활성화(`-P`)되면 Noir는 다음을 수행합니다:
1. 첫 실행 시 규칙 초기화 — [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) 저장소를 `~/.config/noir/passive_rules/`로 클론합니다.
2. 업데이트 확인 — 시작 시 로컬 Git 저장소와 원격을 비교하여 사용 가능한 업데이트를 확인합니다.
3. 사용자 알림 — 규칙이 오래된 경우 구체적인 업데이트 방법과 함께 명확히 경고합니다.
4. 자동 업데이트(옵션) — 설정 시 최신 규칙을 자동으로 가져옵니다.

저장소: https://github.com/owasp-noir/noir-passive-rules

## 새로운 CLI 옵션

- `--passive-scan-auto-update` — 시작 시 저장소에서 규칙을 자동으로 업데이트합니다.
- `--passive-scan-no-update-check` — 업데이트 확인을 완전히 건너뜁니다(에어갭 환경에 유용).

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

기본 규칙은 훌륭한 시작점이지만 조직이나 애플리케이션에 특정한 문제를 찾기 위해 자신만의 규칙을 추가하고 싶을 수 있습니다. 이를 위해서는 새 YAML 규칙 파일을 생성하여 기본 규칙과 같은 디렉토리에 배치하면 됩니다.

이 디렉토리에 추가하는 모든 `.yml` 또는 `.yaml` 파일은 다음에 패시브 스캐너를 실행할 때 자동으로 로드되어 사용됩니다. 이를 통해 기본 규칙 세트를 수정하지 않고도 특정 요구사항에 맞게 Noir의 패시브 스캐닝 기능을 쉽게 확장하고 사용자 정의할 수 있습니다.
