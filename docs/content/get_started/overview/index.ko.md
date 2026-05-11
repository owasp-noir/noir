+++
title = "Noir란?"
description = "OWASP Noir는 정적 분석으로 엔드포인트를 식별하는 공격 표면 탐지 도구입니다."
weight = 1
sort_by = "weight"

+++

{% mascot(mood="hi") %}
안녕! 나는 Noir의 마스코트 학이야. Noir가 어떤 도구인지 소개할게.
{% end %}

Noir는 오픈 소스 공격 표면 탐지 도구입니다. 소스 코드를 읽고 Shadow API와 문서화되지 않은 경로를 포함한 모든 API 엔드포인트를 발견합니다.

보안 팀은 공격자가 노릴 만한 지점을 Noir로 미리 끄집어냅니다. 잊혀진 엔드포인트, 노출된 파라미터, 코드 리뷰에서 빠져나간 숨은 경로 같은 것들이죠. 개발자는 API 문서를 정확하게 유지하고, DAST 파이프라인에 엔드포인트를 넘기고, LLM 기반 SAST와 코드 감사가 실제로 살펴봐야 할 코드를 곧바로 가리키는 데 Noir를 활용합니다.

![noir-usage](./noir-usage.jpg)

## Noir로 무엇을 할 수 있나요?

**숨겨진 것을 찾습니다.** 소스 코드를 정적 분석해 모든 엔드포인트, 파라미터, 헤더, 쿠키를 추출합니다. 아무도 문서화하지 않은 것까지 빠짐없이요.

**어떤 스택이든 다룹니다.** 단일 바이너리로 Crystal, Go, Java, JavaScript, Kotlin, PHP, Python, Ruby, Rust, Swift 등 50개 이상의 프레임워크를 지원합니다. 플러그인이나 언어별 설정도 필요 없습니다.

**AI를 활용합니다.** Noir가 네이티브로 지원하지 않는 프레임워크의 경우, LLM(OpenAI, Ollama 등)을 연결하면 AI가 코드를 분석해줍니다.

**DAST 도구에 공급합니다.** Noir가 소스 코드에서 매핑한 엔드포인트를 ZAP, Burp Suite, Caido에 그대로 흘려보냅니다. 페이지에서 링크되지 않아 크롤러가 놓치던 경로까지 함께 다뤄집니다.

**AI SAST를 진짜 공격 표면으로 가리킵니다.** Noir가 추출한 엔드포인트 인벤토리(진입점, 소스 파일, 파라미터, 태그, 그리고 `--include-callee` 사용 시 각 핸들러가 호출하는 1-hop 함수들)는 LLM 기반 SAST, 코드 감사, 보안 에이전트가 공격자에게 도달 가능한 코드의 버그를 찾는 데 필요한 바로 그 컨텍스트입니다. 모델에게 저장소 전체를 훑게 하지 말고, Noir가 미리 매핑해 둔 공격 표면을 그대로 넘기세요.

**어떤 형식으로든 내보냅니다.** JSON, YAML, OpenAPI 명세, CI/CD용 SARIF, cURL 명령, HTML 보고서, Postman 컬렉션 등 워크플로에 필요한 형식으로 결과를 출력합니다.

## 어떻게 작동하나요?

Noir를 소스 코드에 실행하면 자동으로:

1. 프로젝트가 사용하는 언어와 프레임워크를 **탐지**
2. 코드를 **분석**하여 엔드포인트, 파라미터, 헤더를 추출
3. 원하는 형식으로 결과를 **보고**

{% mermaid() %}
flowchart LR
    SourceCode:::highlight --> Detectors

    subgraph Detectors
        direction LR
        Detector1 & Detector2 & Detector3 --> |Condition| PassiveScan
    end

    PassiveScan --> |Results| BaseOptimizer

    Detectors --> |Techs| Analyzers

    subgraph Analyzers
        direction LR
        CodeAnalyzers & FileAnalyzer & LLMAnalyzer
        CodeAnalyzers --> |Condition| Minilexer
        CodeAnalyzers --> |Condition| Miniparser
    end
   subgraph Optimizer
       direction LR
       BaseOptimizer[Optimizer] --> LLMOptimizer[LLM Optimizer]
       LLMOptimizer[LLM Optimizer] --> OptimizedResult
       OptimizedResult[Result]
   end

    Analyzers --> |Condition| Deliver
    Analyzers --> |Condition| Tagger
    Deliver --> 3rdParty
    BaseOptimizer --> OptimizedResult
    OptimizedResult --> OutputBuilder
    Tagger --> |Tags| BaseOptimizer
    Analyzers --> |Endpoints| BaseOptimizer
    OutputBuilder --> Report:::highlight

    classDef highlight fill:#000,stroke:#333,stroke-width:4px;
{% end %}

## 기여하기

Noir는 오픈 소스이며 모든 기여를 환영합니다. [기여 가이드](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)를 참고하세요.

### 기여자

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/docs/static/CONTRIBUTORS.svg)

---

**다음**: [Noir 설치](@/get_started/installation/index.md)
