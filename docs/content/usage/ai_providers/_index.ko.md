+++
title = "AI 제공업체"
description = "OpenAI, Azure AI, OpenRouter와 로컬·ACP 런타임 같은 AI 제공업체에 Noir를 연결하는 방법입니다."
weight = 3
sort_by = "weight"

+++

Noir의 AI 분석은 클라우드 API, 로컬 모델 서버, ACP 에이전트를 쓸 수 있습니다.

`--ai-provider`에는 아래 표의 프리셋 이름이나 OpenAI 호환 URL(예: `http://localhost:8000/v1`)을 넘깁니다. API 키는 `NOIR_AI_KEY`나 `--ai-key-file`로 넘기세요. `--ai-key`도 되지만, 이 경우 키가 프로세스 목록에 그대로 보입니다.

## 제공업체

| 제공업체 | 유형 | API 키 | 인터넷 | 비고 |
|---|---|---|---|---|
| [OpenAI](openai/) | 클라우드 | 필요 | 필요 | GPT 모델 |
| [xAI](xai/) | 클라우드 | 필요 | 필요 | Grok 모델 |
| [Azure AI](azure/) | 클라우드 | 필요 | 필요 | Foundry 리소스 URL을 직접 지정 |
| [Anthropic](anthropic/) | 클라우드 | 필요 | 필요 | Claude 모델, 네이티브 Messages API |
| [Google Gemini](gemini/) | 클라우드 | 필요 | 필요 | Gemini 모델 |
| [OpenRouter](openrouter/) | 클라우드 | 필요 | 필요 | 키 하나로 여러 업체 모델 사용 |
| [Ollama](ollama/) | 로컬 | 불필요 | 불필요 | Ollama 네이티브 API |
| [vLLM](vllm/) | 로컬 | 불필요 | 불필요 | OpenAI 호환 서버 |
| [LM Studio](lmstudio/) | 로컬 | 불필요 | 불필요 | 로컬 서버가 있는 데스크톱 앱 |
| [ACP](acp/) | 에이전트 | 불필요 | 필요 | Codex, Gemini, Claude 에이전트(각자 로그인) |

## 종료된 연동

*   [GitHub Models 제공업체(종료)](github_marketplace/): GitHub Models는 2026년 7월 30일 종료되었습니다. 기존 Noir 설정을 옮길 때 참고하도록 안내 페이지를 남겨 두었습니다.
