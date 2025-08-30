+++
title = "패시브 스캔 규칙"
description = ""
weight = 1
sort_by = "weight"

[extra]
+++

```yaml
id: rule-id
info:
  name: "규칙의 이름"
  author:
    - "작성자 목록"
    - "다른 작성자"
  severity: "규칙의 심각도 수준 (예: critical, high, medium, low)"
  description: "규칙에 대한 간단한 설명"
  reference:
    - "규칙과 관련된 URL 또는 참조"

matchers-condition: "매처 간에 적용할 조건 (and/or)"
matchers:
  - type: "매처의 유형 (예: word, regex)"
    patterns:
      - "일치시킬 패턴"
    condition: "매처 내에서 적용할 조건 (and/or)"

  - type: "매처의 유형 (예: word, regex)"
    patterns:
      - "일치시킬 패턴"
      - "다른 패턴"
    condition: "매처 내에서 적용할 조건 (and/or)"

category: "규칙의 카테고리 (예: secret, vulnerability)"
techs:
  - "규칙이 적용되는 기술 또는 프레임워크"
  - "다른 기술"
```

## 예제 규칙: PRIVATE_KEY 탐지

```yaml
id: detect-private-key
info:
  name: "PRIVATE_KEY 탐지"
  author:
    - "security-team"
  severity: critical
  description: "코드에서 PRIVATE_KEY의 존재를 탐지합니다"
  reference:
    - "https://example.com/security-guidelines"

matchers-condition: or
matchers:
  - type: word
    patterns:
      - "PRIVATE_KEY"
      - "-----BEGIN PRIVATE KEY-----"
    condition: or

  - type: regex
    patterns:
      - "PRIVATE_KEY\\s*=\\s*['\"]?[^'\"]+['\"]?"
      - "-----BEGIN PRIVATE KEY-----[\\s\\S]*?-----END PRIVATE KEY-----"
    condition: or

category: secret
techs:
  - '*'
```

![](./passive_private_key.png)