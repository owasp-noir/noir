+++
title = "기본 패시브 스캔 규칙"
description = "기본 패시브 스캔 규칙 위치, 자동 업데이트 동작, 사용자 정의 방법."
weight = 2
sort_by = "weight"

+++

Noir의 기본 규칙은 코드에 하드코딩된 시크릿(API 키, 토큰, 개인 키, 연결 문자열)을 찾습니다. `-P`를 켜면 첫 실행에서 규칙을 내려받고, 업데이트를 확인하며, 원하면 자동으로 업데이트합니다.

{% mascot(mood="hacker") %}
패시브 스캔은 엔드포인트 스캔과 같은 패스에서 돌아. 코드 속 시크릿이나 위험한 호출을 파일과 줄 번호로 알려줘.
{% end %}

## 규칙 위치

| OS      | 경로                               |
|---------|------------------------------------|
| macOS   | `~/.config/noir/passive_rules/`    |
| Linux   | `~/.config/noir/passive_rules/`    |
| Windows | `%APPDATA%\noir\passive_rules\`   |

`NOIR_HOME`을 설정하면 규칙은 `$NOIR_HOME/passive_rules/`에 저장됩니다. 실제로 쓰는 디렉터리는 `noir rules path`로 확인할 수 있습니다.

공식 Docker 이미지에는 `/opt/noir/passive_rules`에 규칙 스냅숏이 들어 있습니다. 사용자 디렉터리가 비어 있으면 Noir는 이 스냅숏을 쓰고 클론과 업데이트 확인을 건너뜁니다. 그래서 컨테이너에서는 git이나 네트워크 없이도 `-P`가 동작합니다.

## 자동 초기화와 업데이트 확인

`-P`를 켜면 Noir는 다음을 합니다.
1. 첫 실행 시 [noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules) 저장소를 `~/.config/noir/passive_rules/`로 클론
2. 로컬과 원격 저장소를 비교해 업데이트 확인. 원격 fetch는 하루에 한 번까지만 하고, 그 사이의 스캔은 마지막 fetch 결과와 비교합니다. `--passive-scan-auto-update`와 `noir rules update`는 항상 fetch합니다.
3. 규칙이 오래된 경우 알림
4. 자동 업데이트를 켰다면 규칙 업데이트

저장소: https://github.com/owasp-noir/noir-passive-rules

## CLI 옵션

- `--passive-scan-auto-update`: 시작 시 규칙 자동 업데이트
- `--passive-scan-no-update-check`: 업데이트 확인을 건너뜀(에어갭 환경에 유용). 첫 실행 시의 규칙 자동 초기화도 함께 건너뛰므로, 규칙을 한 번도 내려받지 않은 환경에서는 `~/.config/noir/passive_rules/`에 규칙을 직접 넣거나 `--passive-scan-path`를 사용하세요.

두 옵션은 `~/.config/noir/config.yaml`에서도 설정할 수 있습니다(`passive_scan_auto_update`, `passive_scan_no_update_check`).

스캔과 별개로 규칙을 관리할 수도 있습니다. `noir rules update`는 최신 규칙을 받아오고, `noir rules list`는 설치된 규칙 파일을 보여 주며, `noir rules path`는 규칙 디렉터리를 출력합니다.

## 사용 예시

```bash
# 기본 동작 - 업데이트를 확인하고 뒤처진 경우 알림
noir scan /app -P

# 시작 시 규칙을 자동 업데이트
noir scan /app -P --passive-scan-auto-update

# 업데이트 확인을 완전히 건너뜀
noir scan /app -P --passive-scan-no-update-check
```

## 예시 출력

첫 실행(자동 초기화):
```
⚬ Passive scanner enabled.
⚬ Initializing passive rules directory...
✔ Passive rules initialized successfully.
  ├── Using default passive rules (/home/user/.config/noir/passive_rules).
  └── Loaded 40 valid passive scan rules.
```

업데이트가 있는 경우:
```
⚬ Passive scanner enabled.
▲ Passive rules are 3 commits behind the latest version.
  ├── Run 'git pull' in /home/user/.config/noir/passive_rules to update
  ├── Or use 'git clone https://github.com/owasp-noir/noir-passive-rules.git /home/user/.config/noir/passive_rules' to get the latest rules
  ├── Or run 'noir scan . -P --passive-scan-auto-update' to auto-update on startup
```

자동 업데이트를 켠 경우:
```
⚬ Passive scanner enabled.
⚬ Updating passive rules (3 commits behind)...
✔ Passive rules updated successfully.
```

## 규칙 사용자 정의

같은 디렉터리에 `.yml`이나 `.yaml` 규칙 파일을 넣으면 다음 패시브 스캔에서 기본 규칙과 함께 로드됩니다.
