+++
title = "Step 1: Noir란?"
description = "OWASP Noir는 정적 분석으로 엔드포인트를 식별하는 공격 표면 탐지 도구입니다."
weight = 1
sort_by = "weight"

+++

> **목표**: 설치 전에 Noir가 무엇을 하는지 이해합니다.

Noir는 소스 코드를 분석하여 Shadow API와 문서화되지 않은 경로를 포함한 API 엔드포인트를 발견하는 공격 표면 탐지 도구입니다. 발견된 엔드포인트를 동적 테스트 도구에 직접 전달하여 SAST와 DAST를 연결합니다.

![noir-usage](./noir-usage.jpg)

## Noir로 무엇을 할 수 있나요?

- **숨겨진 엔드포인트 발견** — 소스 코드에서 Shadow API, 문서화되지 않은 경로, 잊혀진 엔드포인트를 탐지
- **50개 이상의 프레임워크 지원** — Rails, Django, Spring, Express, FastAPI 등 하나의 도구로 분석
- **AI로 미지원 코드도 분석** — LLM을 활용하여 미지원 프레임워크에서도 엔드포인트를 탐지
- **DAST 도구에 전달** — ZAP, Burp Suite, Caido에 결과를 직접 전달
- **다양한 형식으로 내보내기** — JSON, YAML, OpenAPI, SARIF, cURL, HTML 보고서 등

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

**다음 단계**: [Step 2: Noir 설치](@/get_started/installation/index.md)
