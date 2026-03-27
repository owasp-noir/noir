+++
title = "AI 제공업체"
description = "OpenAI, xAI와 Ollama/LM Studio 같은 로컬 모델, 그리고 ACP 기반 에이전트까지 Noir를 다양한 AI 제공업체에 연결하는 방법을 안내합니다."
weight = 3
sort_by = "weight"

+++

Noir의 AI 기반 분석은 다양한 대규모 언어 모델(LLM) 제공업체와 함께 사용할 수 있습니다. 강력한 클라우드 기반 모델을 사용하든 개인정보 보호 및 오프라인 사용을 위한 로컬 모델을 사용하든, Noir가 모든 것을 지원합니다.

## 제공업체 비교

| 제공업체 | 유형 | API 키 | 인터넷 | 적합한 용도 |
|---|---|---|---|---|
| [OpenAI](openai/) | 클라우드 | 필요 | 필요 | 높은 정확도, 최신 모델 |
| [xAI](xai/) | 클라우드 | 필요 | 필요 | Grok 모델 |
| [Azure AI](azure/) | 클라우드 | 필요 | 필요 | 기업 환경, 컴플라이언스 |
| [GitHub Marketplace](github_marketplace/) | 클라우드 | GitHub PAT | 필요 | GitHub 생태계 사용자 |
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
    *   [GitHub Marketplace](github_marketplace/)
    *   [OpenRouter](openrouter/)
*   **로컬 모델 제공업체**:
    *   [Ollama](ollama/)
    *   [vLLM](vllm/)
    *   [LM Studio](lmstudio/)
*   **ACP 에이전트 제공업체**:
    *   [ACP (Codex/Gemini/Claude/사용자 정의)](acp/)

이 가이드를 따라하면 AI의 힘을 코드 분석 워크플로에 쉽게 통합할 수 있습니다.
