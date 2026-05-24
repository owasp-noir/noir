+++
title = "Noir란?"
description = "OWASP Noir는 소스 코드에서 엔드포인트를 추출해, 사람 리뷰어, AI 감사자, DAST 스캐너에 공급하는 SAST 도구입니다."
weight = 1
sort_by = "weight"
next_page_path = "/get_started/installation/"
next_page_label = "Noir 설치"

+++

{% mascot(mood="hi") %}
안녕! 나는 Noir의 마스코트 학이야. Noir가 어떤 도구인지 소개할게.
{% end %}

Noir는 오픈 소스 SAST 도구입니다. 소스 코드를 읽어 애플리케이션이 노출하는 엔드포인트(경로, 메서드, 파라미터, 헤더, 쿠키, 그리고 그 뒤의 소스 파일)를 추출합니다. Shadow API와 문서화되지 않은 경로도 같은 인벤토리에 함께 나옵니다. 별도의 모드가 아닙니다.

이 인벤토리는 세 대상에게 전달됩니다:

- **사람 리뷰어.** 보안 엔지니어와 코드 감사자는 저장소 전체를 훑는 대신, 공격자가 도달할 수 있는 진입점과 그 주변 파일/파라미터/태그에 곧바로 집중할 수 있습니다.
- **AI 감사자.** LLM 기반 SAST 에이전트는 같은 진입점 목록에 더해, 엔드포인트별 리뷰 컨텍스트(`--include callee`로 1-hop callee, `--ai-context`로 guards/sinks/validators/signals)까지 받습니다.
- **DAST 도구.** ZAP, Burp Suite, Caido는 크롤링만으로는 절대 닿지 못했을 경로까지 포함된 실제 라우트 목록을 스캔 대상으로 받습니다.

![noir-usage](./noir-usage.jpg)

## Noir가 하는 일

**엔드포인트 추출.** 정적 분석으로 소스에서 엔드포인트, 파라미터, 헤더, 쿠키를 끌어냅니다. 아무도 문서화하지 않은 것까지 포함해서요.

**스택 전반 커버.** 단일 바이너리로 Crystal, Go, Java, JavaScript, Kotlin, PHP, Python, Ruby, Rust, Swift 등 50개 이상의 프레임워크를 지원합니다. 플러그인이나 언어별 설정은 필요 없습니다.

**LLM 폴백.** 네이티브로 지원하지 않는 프레임워크거나 정적 규칙으로 처리하기 어려운 커스텀 라우팅이라면, LLM(OpenAI, Ollama 등)을 연결해 빈 자리를 채웁니다.

**DAST 스캐너에 공급.** 엔드포인트를 ZAP, Burp Suite, Caido로 프록시 타깃처럼 흘려보내거나, OpenAPI로 내보내 임포트시킵니다. 페이지에서 링크되지 않아 크롤러가 놓치던 경로도 스캔 범위에 들어옵니다.

**AI SAST에 쓸 만한 컨텍스트 제공.** Noir가 추출한 엔드포인트 인벤토리(진입점, 소스 파일, 파라미터, 태그, 그리고 `--include callee` 사용 시 각 핸들러가 호출하는 1-hop 함수들)는 LLM 기반 SAST, 코드 감사자, 보안 에이전트가 공격자 도달 가능한 코드의 버그를 찾는 데 필요한 바로 그 컨텍스트입니다. `--ai-context`를 켜면 한 단계 더 나아가, 엔드포인트별로 집약된 리뷰 컨텍스트(guards, callees, sinks, validators, signals)까지 함께 붙어서 모델이 다시 찾아낼 필요가 없습니다. 모델에게 저장소 전체를 훑게 하는 대신, Noir가 매핑해 둔 표면을 그대로 넘기세요.

**다음 도구가 읽을 형식으로 출력.** JSON, YAML, OpenAPI 명세, CI/CD용 SARIF, cURL, HTTPie, HTML 보고서, Postman 컬렉션 등 파이프라인의 다음 도구가 기대하는 형식으로 결과가 나옵니다.

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
