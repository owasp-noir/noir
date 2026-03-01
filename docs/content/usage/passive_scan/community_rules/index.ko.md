+++
title = "커뮤니티 기여 패시브 스캔 규칙"
description = "커뮤니티 기여 패시브 스캔 규칙 사용 방법."
weight = 3
sort_by = "weight"

+++

기본 규칙 외에 커뮤니티 기여 규칙을 사용하여 더 광범위한 보안 문제를 탐지할 수 있습니다.

## 저장소

*   **[owasp-noir/noir-passive-rules](https://github.com/owasp-noir/noir-passive-rules)**

## 설치

Noir 구성 디렉터리에 저장소를 클론합니다:

```bash
git clone https://github.com/owasp-noir/noir-passive-rules ~/.config/noir/passive_rules/
```

커뮤니티 규칙은 다음 패시브 스캔(`-P`) 시 자동으로 로드됩니다.