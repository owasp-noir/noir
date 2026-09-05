+++
title = "설정 파일 사용하기"
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

설정 파일의 값은 명령줄 인자로 재정의할 수 있습니다. 기본 위치가 아닌 곳에서 설정을 불러오려면 `--config-file <경로>`를 사용하세요:

```bash
noir scan . --config-file ./ci/noir.yaml
```

설정 파일은 `noir config` 로도 직접 다룰 수 있습니다:

```bash
noir config init   # 기본 설정 생성 (멱등)
noir config show   # 활성 파일 출력
noir config path   # 해석된 경로 출력
```

## 디렉터리 구조

```
~/.config/noir/
├── config.yaml          # 설정 파일
├── cache/
│   └── ai/              # LLM 응답 캐시
└── passive_rules/       # 패시브 스캔 규칙
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

# 프로브 대상 기본 URL. exclude_codes / status_codes 에도 필요합니다
url: "https://api.example.com"

# 특정 상태 코드 제외 (대상 URL이 있어야 하므로 위 `url`과 함께 씁니다)
exclude_codes: "404,500"

# 기본적으로 모든 태거 활성화
all_taggers: true

# 엔드포인트마다 1-hop 핸들러 callee 첨부
include_callee: true

# AI 리뷰 컨텍스트(guards, callee, sources, sinks, validators, signals) 첨부
ai_context: true

# 기본 AI 제공업체 및 모델
ai_provider: "openai"
ai_model: "gpt-5.5"
```

위 설정은 다음 명령과 동일합니다:

```bash
noir scan /path/to/my/project -f json -u https://api.example.com --exclude-codes "404,500" -T \
  --include callee --ai-context \
  --ai-provider openai --ai-model gpt-5.5
```

