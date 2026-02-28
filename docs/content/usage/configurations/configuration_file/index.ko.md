+++
title = "구성 파일 사용하기"
description = "Noir의 기본 옵션을 설정하기 위해 `config.yaml` 파일을 사용하는 방법을 알아보세요. 이는 워크플로를 간소화하고 일관된 스캔을 보장하는 좋은 방법입니다."
weight = 1
sort_by = "weight"

+++

Noir 실행을 더 쉽고 일관되게 만들기 위해 구성 파일을 사용하여 많은 명령줄 플래그의 기본값을 설정할 수 있습니다. 이렇게 하면 스캔을 실행할 때마다 같은 옵션을 입력할 필요가 없습니다.

## 구성 파일 위치

Noir는 운영 체제에 따라 특정 디렉토리에서 `config.yaml`이라는 파일을 찾습니다:

| OS | 경로 |
|---|---|
| macOS | `~/.config/noir/` |
| Linux | `~/.config/noir/` |
| Windows | `%APPDATA%\noir\` |

이 파일에서 정의한 모든 설정이 기본값으로 사용되지만 명령줄에서 다른 값을 제공하여 언제든지 재정의할 수 있습니다.

## Noir 홈 디렉터리 구조

Noir는 동일한 홈 디렉터리 경로 아래에 구성과 캐시를 저장합니다(위 표의 경로 참고). 일반적인 구조는 다음과 같습니다:

```
~/.config/noir/
├── config.yaml          # 기본 구성 파일
├── cache/
│   └── ai/              # AI 기반 분석을 위한 LLM 응답 캐시
└── passive_rules/       # Passive Scan을 위한 룰 디렉토리
```

- config.yaml: 기본 구성 파일
- cache/ai: 반복 분석 속도 향상과 비용 절감을 위한 AI 응답 캐시 저장 위치
- passive_rules: Passive Scan 규칙 파일 저장 위치

## `config.yaml` 예제

다음은 일반적인 설정이 포함된 `config.yaml` 파일의 예제입니다:

```yaml
---
# 스캔의 기본 베이스 경로
base: "/path/to/my/project"

# 출력에서 항상 색상 사용
color: true

# 기본 출력 형식
format: "json"

# 특정 상태 코드 제외
exclude_codes: "404,500"

# 기본적으로 모든 태거 활성화
all_taggers: true

# 기본 AI 제공자 및 모델
ai_provider: "openai"
ai_model: "gpt-4o"
```

이 구성으로 단순히 `noir`를 실행하면 다음 명령과 동일합니다:

```bash
noir -b /path/to/my/project -f json --exclude-codes "404,500" -T --ai-provider openai --ai-model gpt-4o
```

구성 파일을 사용하면 특정 요구사항에 맞춤화된 개인화되고 효율적인 워크플로를 만들 수 있습니다.