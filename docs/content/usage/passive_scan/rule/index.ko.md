+++
title = "패시브 스캔 규칙"
description = "YAML을 사용하여 코드베이스의 보안 문제를 탐지하는 커스텀 패시브 스캔 규칙을 만듭니다."
weight = 1
sort_by = "weight"

+++

```yaml
id: rule-id
info:
  name: "규칙의 이름"
  author:
    - "작성자 목록"
    - "다른 작성자"
  severity: "규칙의 심각도 수준 (critical, high, medium, low 중 하나)"
  description: "규칙에 대한 간단한 설명"
  reference:
    - "규칙과 관련된 URL 또는 참조"

matchers-condition: "매처 간에 적용할 조건 (and/or)"
matchers:
  - type: "매처의 유형 (word, regex 중 하나)"
    patterns:
      - "일치시킬 패턴"
    condition: "매처 내에서 적용할 조건 (and/or)"

  - type: "매처의 유형 (word, regex 중 하나)"
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

<img src="./passive_private_key.png" alt="BEGIN PRIVATE KEY 줄과 해당 파일을 함께 보여 주며 critical 등급의 PRIVATE_KEY 를 보고하는 패시브 스캔 결과." width="787" height="286" loading="lazy" decoding="async">

## 규칙 필드 관련 참고사항

* `severity`와 `matchers[].type`은 정해진 값만 허용합니다. 다른 값을 쓰면 규칙이 일부만 적용되는 것이 아니라 유효하지 않은 규칙으로 판단되어 `Skipped invalid passive rule` 메시지와 함께 통째로 건너뜁니다. `category`는 자유 형식입니다.
* 최소 심각도보다 낮은 탐지 결과는 리포트에서 걸러지며, 기본 최소 심각도는 `high`입니다. 따라서 `severity: medium`이나 `severity: low` 규칙은 `--passive-scan-severity`로 기준을 낮추기 전까지 아무것도 보고하지 않습니다.
* `techs`는 탐지 결과에 함께 기록되는 메타데이터입니다. 규칙이 검사할 파일을 제한하지 않으며, 로드된 모든 규칙은 스캔 대상 모든 파일에 대해 평가됩니다.
* 매처는 **줄 단위로** 평가됩니다. 탐지 결과는 한 줄이며, 모든 매처(그리고 그 안의 모든 패턴)가 그 한 줄에서 만족되어야 합니다. 따라서 `-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----`처럼 여러 줄에 걸치도록 작성한 `regex` 패턴은 그 자체로는 아무것도 탐지하지 못합니다. 시작 표시를 잡는 `word` 매처와 함께 사용하세요.
* `id`는 전체 규칙 집합에서 유일해야 합니다. 같은 id를 다시 쓰는 규칙은 `Skipped duplicate passive rule id` 메시지와 함께 건너뜁니다. JSON 출력과 SARIF의 `ruleId`가 탐지 결과를 식별하는 값이 바로 id이기 때문입니다.
* 하나의 규칙 파일에 `---`로 구분된 YAML 문서를 여러 개 넣을 수 있으며, 각 문서는 별도의 규칙으로 로드됩니다.
* 매처가 모두 컴파일에 실패한 규칙(깨진 `regex` 패턴)은 절대 동작할 수 없으므로, 로드된 것으로 집계하지 않고 다른 유효하지 않은 규칙과 동일하게 거부합니다.
* `patterns` 의 각 항목은 비어 있으면 안 됩니다. 빈 패턴(명시적인 `''`, 또는 값 없이 `- ` 만 적어 YAML 이 null 로 읽는 항목)은 스캔하는 모든 파일의 모든 줄과 일치하므로, 그런 패턴이 있는 규칙은 리포트를 뒤덮기 전에 거부합니다.
