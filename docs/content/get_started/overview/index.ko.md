+++
title = "개요"
description = "OWASP Noir가 무엇인지, 어떻게 작동하는지, 그리고 목표가 무엇인지 알아보세요. 이 페이지는 프로젝트와 주요 기능에 대한 개괄적인 소개를 제공합니다."
weight = 1
sort_by = "weight"

+++

Noir는 소스 코드를 분석하여 섀도우 API, 관리되지 않는 엔드포인트, 숨겨진 경로 등을 발견함으로써 SAST와 DAST의 격차를 메웁니다.

소스 코드를 단일 정보원으로 사용하여 포괄적인 공격 표면 데이터를 제공하고, DAST 도구와 통합하여 DevSecOps 파이프라인의 사각지대를 제거합니다.

## 주요 기능

- **공격 표면 발견**: 숨겨진 엔드포인트와 Shadow API를 포함한 전체 공격 표면 식별
- **AI 기반 분석**: LLM을 사용하여 지원되지 않는 언어와 프레임워크에서 엔드포인트 탐지
- **SAST-DAST 연결**: 발견된 엔드포인트를 DAST 도구에 제공하여 포괄적인 보안 스캔 지원
- **DevSecOps 지원**: ZAP, Burp Suite, Caido 등과 통합되며 CI/CD 파이프라인에 적합
- **다양한 출력 형식**: JSON, YAML, OpenAPI 등 다양한 형식으로 내보내기

[GitHub](https://github.com/owasp-noir/noir) | [OWASP 프로젝트 페이지](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## 작동 방식

Noir는 [Crystal](https://crystal-lang.org)로 구축되었으며 다음 구성 요소를 사용합니다:

*   **탐지기**: 코드베이스의 기술 식별
*   **분석기**: 코드를 파싱하여 엔드포인트와 매개변수 탐색
*   **LLM 분석기**: AI를 사용하여 지원되지 않는 프레임워크의 엔드포인트 발견
*   **패시브 스캐너 및 태거**: 취약점 식별 및 컨텍스트 태그 추가
*   **전달**: 결과를 외부 도구로 전송
*   **출력 빌더**: 다양한 형식의 보고서 생성

## 프로젝트 목표

숨겨지고 문서화되지 않은 엔드포인트를 포함한 포괄적인 엔드포인트 발견을 통해 정적 코드 분석과 동적 보안 테스트를 연결하여 더 효과적인 DAST 스캔을 가능하게 합니다.

향후 언어 지원 확대, 분석 정확도 개선, AI 기능 강화를 계획하고 있습니다.

## 기여하기

Noir는 오픈 소스이며 모든 기여를 환영합니다. 자세한 내용은 [기여 가이드](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)를 참조하세요.

### 기여자

Noir에 기여해 주신 모든 분께 감사드립니다! ♥️

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/docs/static/CONTRIBUTORS.svg)

## 행동 강령

GitHub의 [행동 강령](https://github.com/owasp-noir/noir/blob/main/CODE_OF_CONDUCT.md)을 확인하세요.

## 도움 및 피드백

질문이나 피드백이 있으면 GitHub [토론](https://github.com/orgs/owasp-noir/discussions) 또는 [이슈](https://github.com/owasp-noir/noir/issues)를 이용하세요.
