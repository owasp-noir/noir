+++
title = "사용 가이드"
description = "Noir 사용법: 지원 기술, 출력 형식, AI 통합, 추가 기능."
weight = 2
sort_by = "weight"


[cascade]
toc = true

+++

Noir를 실행하고 개별 기능을 설정하는 데 필요한 레퍼런스입니다.

## 주요 영역

*   **[CLI 명령어](cli_commands/)**: v1 서브커맨드(`scan`, `list`, `cache`, `config`, `rules`, `completion`, `version`, `help`) 레퍼런스. v0 호환 메모 포함.
*   **[지원되는 기술](supported/)**: Noir가 분석할 수 있는 프로그래밍 언어, 프레임워크, 명세.
*   **[설정](configurations/)**: 설정 파일과 셸 자동완성.
*   **[출력 형식](output_formats/)**: JSON, YAML, OpenAPI 등 Noir가 내보낼 수 있는 형식.
*   **[패시브 스캔](passive_scan/)**: 스캔 중에 잠재적 보안 이슈를 잡아내는 룰 기반 점검.
*   **[GitHub Action](github_action/)**: 공식 GitHub Action으로 CI에서 Noir 실행.
*   **[추가 기능](more_features/)**: Tagger, Deliver, diff 스캔, DAST 파이프라인.
*   **[AI 기반 분석](../get_started/ai_power/)**: Noir의 LLM 통합이 어떻게 작동하고 언제 활성화하는지.
*   **[AI 제공업체](ai_providers/)**: LLM 폴백 경로를 위해 OpenAI, Ollama 등 제공업체와 연결하는 방법.