+++
template = "landing.html"

[extra]
version = "v0.27.1"

[extra.hero]
title = " "
badge = "v0.27.1"
description = "코드베이스 내 모든 엔드포인트를 자동으로 탐지하는 고급 하이브리드 분석 도구. 섀도우 API와 문서화되지 않은 엔드포인트까지 놓치지 않고 찾아냅니다."
image = "../images/noir-wallpaper.jpg"
cta_buttons = [
    { text = "시작하기", url = "./get_started/overview", style = "primary" },
    { text = "GitHub에서 보기", url = "https://github.com/owasp-noir/noir", style = "secondary" },
]

[extra.features_section]
title = "주요 기능"
description = "OWASP Noir의 공격 표면 탐지 및 분석을 위한 핵심 기능을 발견하세요."

[[extra.features]]
title = "공격 표면 발견"
desc = "소스 코드를 분석하여 숨겨진 엔드포인트, Shadow API 및 기타 보안 사각지대를 포함한 애플리케이션의 전체 공격 표면을 발견합니다."
icon = "fa-solid fa-code"

[[extra.features]]
title = "다중 언어 지원"
desc = "다양한 프로그래밍 언어와 프레임워크를 지원하여 다양한 프로젝트 포트폴리오 전반에서 광범위한 호환성을 보장합니다."
icon = "fa-solid fa-globe"

[[extra.features]]
title = "DevSecOps 지원"
desc = "CI/CD 파이프라인 및 보안 워크플로우에 원활하게 통합되도록 설계되었으며, cURL, ZAP, Caido 등 인기 도구를 지원합니다."
icon = "fa-solid fa-gears"

[[extra.features]]
title = "AI 기반 분석"
desc = "대규모 언어 모델(LLM)을 활용하여 네이티브로 지원되지 않는 언어나 프레임워크에서도 엔드포인트를 탐지하여 어떤 엔드포인트도 놓치지 않습니다."
icon = "fa-solid fa-robot"

[[extra.features]]
title = "SAST-DAST 연결"
desc = "발견된 엔드포인트를 ZAP, Burp Suite 같은 DAST 도구에 제공하여 정적 코드 분석과 동적 테스트를 연결하고 더 포괄적인 보안 스캔을 가능하게 합니다."
icon = "fa-solid fa-bridge"

[[extra.features]]
title = "유연한 출력 형식"
desc = "JSON, YAML, OpenAPI를 포함한 다양한 형식으로 명확하고 실행 가능한 결과를 생성하여 다른 도구에서 데이터를 쉽게 사용할 수 있습니다."
icon = "fa-solid fa-file-export"

[extra.trust_section]
title = "개발 환경"
logos = [
    { src = "./resoruces/owasp.png", alt = "OWASP" },
    { src = "./resoruces/crystal.png", alt = "Crystal" },
]

[extra.final_cta_section]
title = "오픈 소스 프로젝트"
description = "OWASP Noir는 커뮤니티가 ❤️로 구축한 오픈 소스 프로젝트입니다. 기여하고 싶으시다면 기여 가이드를 참조하고 멋진 변경 사항과 함께 풀 리퀘스트를 제출해 주세요!"
button = { text = "기여 가이드 보기", url = "https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" }
image = "https://github.com/owasp-noir/noir/raw/main/docs/static/CONTRIBUTORS.svg"
+++
