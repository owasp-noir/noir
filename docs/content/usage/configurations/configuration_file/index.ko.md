+++
title = "구성 파일 사용하기"
description = "config.yaml 파일로 Noir 기본 옵션을 설정합니다."
weight = 1
sort_by = "weight"

+++

`config.yaml` 파일로 기본 옵션을 설정하여 일관된 스캔을 수행할 수 있습니다.

## 파일 위치

| OS | 경로 |
|---|---|
| macOS | `~/.config/noir/` |
| Linux | `~/.config/noir/` |
| Windows | `%APPDATA%\noir\` |

설정 파일의 값은 명령줄 인자로 재정의할 수 있습니다.

## 디렉터리 구조

```
~/.config/noir/
├── config.yaml          # 기본 구성 파일
├── cache/
│   └── ai/              # AI 기반 분석을 위한 LLM 응답 캐시
└── passive_rules/       # Passive Scan을 위한 룰 디렉토리
```

## `config.yaml` 예제

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

위 설정은 다음 명령과 동일합니다:

```bash
noir -b /path/to/my/project -f json --exclude-codes "404,500" -T --ai-provider openai --ai-model gpt-4o
```

