+++
title = "AI 제공업체"
description = "OpenAI, Azure AI, OpenRouter와 Ollama, LM Studio, ACP 같은 지원되는 AI 제공업체에 Noir를 연결하는 방법을 안내합니다."
weight = 3
sort_by = "weight"

+++

Noir의 LLM 분석은 클라우드 API, 오프라인·프라이버시가 필요할 때의 로컬 런타임, ACP 에이전트를 지원합니다. 기존 설정을 찾을 수 있도록 종료된 연동은 별도로 안내합니다.

## 제공업체 비교

| 제공업체 | 유형 | API 키 | 인터넷 | 적합한 용도 |
|---|---|---|---|---|
| [OpenAI](openai/) | 클라우드 | 필요 | 필요 | 높은 정확도, 최신 모델 |
| [xAI](xai/) | 클라우드 | 필요 | 필요 | Grok 모델 |
| [Azure AI](azure/) | 클라우드 | 필요 | 필요 | 기업 환경, 컴플라이언스 |
| [Anthropic](anthropic/) | 클라우드 | 필요 | 필요 | Claude 모델, 네이티브 API |
| [Google Gemini](gemini/) | 클라우드 | 필요 | 필요 | Gemini 모델 |
| [OpenRouter](openrouter/) | 클라우드 | 필요 | 필요 | 하나의 API로 여러 모델 접근 |
| [Ollama](ollama/) | 로컬 | 불필요 | 불필요 | 개인정보 보호, 오프라인, 무료 |
| [vLLM](vllm/) | 로컬 | 불필요 | 불필요 | 고성능 로컬 추론 |
| [LM Studio](lmstudio/) | 로컬 | 불필요 | 불필요 | GUI 기반 로컬 모델 |
| [ACP](acp/) | 에이전트 | 다양 | 다양 | 에이전트 기반 워크플로 (Codex, Gemini, Claude) |

## 상세 가이드

*   **클라우드 기반 제공업체**:
    *   [OpenAI](openai/)
    *   [xAI](xai/)
    *   [Azure AI](azure/)
    *   [Anthropic](anthropic/)
    *   [Google Gemini](gemini/)
    *   [OpenRouter](openrouter/)
*   **로컬 모델 제공업체**:
    *   [Ollama](ollama/)
    *   [vLLM](vllm/)
    *   [LM Studio](lmstudio/)
*   **ACP 에이전트 제공업체**:
    *   [ACP (Codex/Gemini/Claude/사용자 정의)](acp/)

## 종료된 연동

*   **[GitHub Models 제공업체(종료)](github_marketplace/)**: GitHub Models는 2026년 7월 30일 종료되었습니다. 기존 Noir 설정을 옮길 때 참고할 수 있도록 안내 페이지를 남겨 두었습니다.
