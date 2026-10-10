+++
title = "Anthropic과 함께 Noir 사용하기"
description = "Anthropic 네이티브 Messages API로 Claude 모델을 Noir와 연결하는 방법입니다."
weight = 4
sort_by = "weight"

+++

`anthropic` 프리셋은 [Anthropic](https://www.anthropic.com)의 OpenAI 호환 레이어가 아니라 네이티브 Messages API(`/v1/messages`)를 사용합니다. Noir가 요청하는 엔드포인트 스키마는 `output_config.format`으로 전달되므로 Claude의 응답이 그 형식을 따릅니다.

## 설정

1.  **API 키**: [Claude Console](https://platform.claude.com/settings/keys)에서 발급하세요.
2.  **모델**: `claude-opus-5-5`나 `claude-sonnet-5-5` 같은 모델 ID를 고르세요.

## 사용 방법

```bash
noir scan ./myapp \
     --ai-provider=anthropic \
     --ai-model=claude-opus-5-5 \
     --ai-key=sk-ant-...
```

`--ai-key`가 없으면 `NOIR_AI_KEY`, 그다음 `ANTHROPIC_API_KEY`를 읽습니다:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
noir scan ./myapp --ai-provider=anthropic --ai-model=claude-sonnet-5-5
```

## 참고

- Messages API 앞단의 게이트웨이도 쓸 수 있습니다: `--ai-provider=https://gw.example/anthropic/v1/messages`. `api.anthropic.com` URL은 `/chat/completions`로 끝나지 않는 한 네이티브 API를 사용합니다.
- 모델이나 게이트웨이가 구조화 출력 요청을 거부하면, Noir는 그 실행이 끝날 때까지 이를 빼고 프롬프트의 JSON 지시에 맡깁니다.
- 샘플링이 고정된 모델(Claude Opus 4.7 이후)에는 `temperature`를 보내지 않습니다.
- 응답 하나는 출력 토큰 16,000개로 제한됩니다. 이 한도에서 잘린 응답은 잘림으로 보고되며, 잘리기 전까지 완성된 엔드포인트는 유지됩니다.
- `--ai-agent`는 Claude의 네이티브 도구 호출을 사용합니다 (`anthropic`은 기본 `--ai-native-tools-allowlist`에 포함).
- `--ai-stream`은 이 제공업체에는 적용되지 않습니다.
