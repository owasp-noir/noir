+++
title = "지원되는 기술"
description = "Noir가 지원하는 기술: 프로그래밍 언어, 프레임워크, API 명세."
weight = 1
sort_by = "weight"

+++

Noir가 분석할 수 있는 대상:

*   **[언어 및 프레임워크](language_and_frameworks/)**: Noir가 엔드포인트와 파라미터를 추출하는 프로그래밍 언어와 웹 프레임워크.
*   **[명세](specification/)**: OpenAPI(Swagger), RAML, HAR 등 Noir가 파싱할 수 있는 API·데이터 명세 형식.
*   **[Callee 커버리지](callee_coverage/)**: AI SAST와 코드 리뷰를 위해 best-effort 1-hop handler callee를 내보내는 프레임워크.
*   **[AI 컨텍스트](ai_context_coverage/)**: `--ai-context`로 각 엔드포인트의 guard, sink, validator, signal을 AI 리뷰용 컨텍스트 객체 하나로 집계.
*   **[모바일 앱](mobile/)**: Android·iOS 앱의 딥링크 진입점(커스텀 스킴, 인텐트, 유니버설 링크)을 추출해 이를 처리하는 코드와 연결하는 방식.
*   **[CLI 앱](cli/)**: 21개 언어에 걸쳐 CLI 프로그램의 커맨드라인 공격 표면(서브커맨드, 플래그, 위치 인자, 사용되는 환경 변수)을 매핑하는 방식.
