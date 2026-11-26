+++
title = "FAQ"
description = "OWASP Noir에 관해 자주 묻는 질문."
weight = 3
sort_by = "weight"
schema_type = "FAQ"
faq_questions = [
  "OWASP Noir란 무엇인가요?",
  "Noir를 어떻게 설치하나요?",
  "Noir는 어떤 언어와 프레임워크를 지원하나요?",
  "Noir에 어떻게 기여할 수 있나요?",
  "Noir는 무료인가요?",
  "다른 보안 도구와 어떻게 통합하나요?",
  "결과를 어떻게 내보내나요?",
  "Noir가 내 코드를 밖으로 보내나요?",
  "버그 보고나 기능 요청은 어떻게 하나요?"
]
faq_answers = [
  "소스 코드를 정적 분석해 API 엔드포인트, 웹 페이지 등 공격 표면 진입점을 발견하는 오픈 소스 도구입니다.",
  "Homebrew, Snapcraft, Docker 등으로 설치합니다. 설치 페이지를 참조하세요.",
  "지원 언어 및 프레임워크 페이지에서 전체 목록을 확인하세요.",
  "기여 가이드를 읽고 시작하세요.",
  "네, MIT 라이선스의 무료 오픈 소스입니다. 상업적 용도로도 자유롭게 사용할 수 있습니다.",
  "ZAP, Burp Suite, Caido 등과 통합할 수 있습니다. DAST 파이프라인 가이드를 참조하세요.",
  "JSON, YAML, OpenAPI 명세, cURL 등 여러 형식으로 내보냅니다. 출력 형식 섹션을 참조하세요.",
  "아니요. 기본 noir scan은 네트워크를 쓰지 않습니다. 옵션을 줄 때만 밖으로 나갑니다. --ai-provider는 소스 코드를 LLM 제공업체로 보내고, -P는 git으로 규칙을 내려받고, --probe는 대상에 요청을 보내고, --export 옵션은 찾은 엔드포인트 목록을 보냅니다.",
  "GitHub 이슈를 열어 버그를 알리거나 기능을 요청해 주세요."
]

+++

{% mascot(mood="question") %}
여기 없는 질문이 있어? 디스커션에 올려주면 추가할게.
{% end %}

### OWASP Noir란 무엇인가요?

소스 코드를 정적 분석해 API 엔드포인트, 웹 페이지 등 공격 표면 진입점을 발견하는 오픈 소스 도구입니다.

### Noir를 어떻게 설치하나요?

Homebrew, Snapcraft, Docker 등으로 설치합니다. [설치](@/get_started/installation/index.ko.md) 페이지를 참조하세요.

### Noir는 어떤 언어와 프레임워크를 지원하나요?

[지원 언어 및 프레임워크](@/usage/supported/language_and_frameworks/index.ko.md) 페이지에서 전체 목록을 확인하세요.

### Noir에 어떻게 기여할 수 있나요?

[기여 가이드](https://github.com/owasp-noir/noir/blob/main/.github/CONTRIBUTING.md)를 읽고 시작하세요.

### Noir는 무료인가요?

네, MIT 라이선스의 무료 오픈 소스입니다. 상업적 용도로도 자유롭게 사용할 수 있습니다.

### 다른 보안 도구와 어떻게 통합하나요?

ZAP, Burp Suite, Caido 등과 통합할 수 있습니다. [DAST 파이프라인](@/usage/more_features/pipeline-for-dast/index.ko.md) 가이드를 참조하세요.

### 결과를 어떻게 내보내나요?

JSON, YAML, OpenAPI 명세, cURL 등 여러 형식으로 내보냅니다. [출력 형식](@/usage/output_formats/_index.ko.md) 섹션을 참조하세요.

### Noir가 내 코드를 밖으로 보내나요?

아니요. 기본 `noir scan`은 네트워크를 쓰지 않습니다. 아래 옵션을 줄 때만 밖으로 나갑니다.

- `--ai-provider`는 분석할 소스 코드를 LLM 제공업체로 보냅니다. 자격 증명 파일은 보내지 않습니다. [전송되는 내용](@/get_started/ai_power/index.ko.md)을 참조하세요
- `-P`(패시브 스캔)는 규칙 저장소를 `git clone`하거나 `git fetch`합니다. 코드는 보내지 않으며, `--passive-scan-path`나 `--passive-scan-no-update-check`를 주면 내려받지 않습니다. [기본 패시브 스캔 규칙](@/usage/passive_scan/default_rules/index.ko.md)을 참조하세요
- `--probe`와 `--probe-via`는 찾은 엔드포인트의 HTTP 요청을 `-u`로 준 대상에 보냅니다. [다른 도구로 결과 전송하기](@/usage/more_features/deliver/index.ko.md)를 참조하세요
- `--export-es`, `--export-opensearch`, `--export-webhook`은 찾은 엔드포인트 목록을 보냅니다. 코드는 보내지 않습니다. [다른 도구로 결과 전송하기](@/usage/more_features/deliver/index.ko.md)를 참조하세요

### 버그 보고나 기능 요청은 어떻게 하나요?

[GitHub 이슈](https://github.com/owasp-noir/noir/issues)를 열어 버그를 알리거나 기능을 요청해 주세요.
