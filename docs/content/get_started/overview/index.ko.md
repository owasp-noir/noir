+++
title = "개요"
description = "OWASP Noir가 무엇인지, 어떻게 작동하는지, 그리고 목표가 무엇인지 알아보세요. 이 페이지는 프로젝트와 주요 기능에 대한 개괄적인 소개를 제공합니다."
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noir는 보안 전문가와 개발자가 애플리케이션의 공격 표면을 식별하는 데 도움이 되도록 설계된 오픈 소스 도구입니다. 소스 코드에 대한 정적 분석을 수행하여 Noir는 공격자가 대상으로 삼을 수 있는 API 엔드포인트, 웹 페이지 및 기타 잠재적 진입점을 발견할 수 있습니다.

이로 인해 화이트박스 보안 테스트와 견고한 보안 파이프라인 구축에 매우 귀중한 도구가 됩니다.

[GitHub](https://github.com/owasp-noir/noir) | [OWASP 프로젝트 페이지](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## 작동 방식

Noir는 [Crystal](https://crystal-lang.org) 프로그래밍 언어로 구축되었으며 코드를 분석하기 위해 함께 작동하는 여러 핵심 구성 요소로 구성됩니다:

*   **탐지기**: 코드베이스에서 사용되는 기술을 식별합니다.
*   **분석기**: 코드를 파싱하여 엔드포인트, 매개변수 및 기타 흥미로운 정보를 찾습니다.
*   **패시브 스캐너 및 태거**: 규칙을 사용하여 잠재적 취약점을 식별하고 발견 사항에 컨텍스트 태그를 추가합니다.
*   **전달**: 추가 분석을 위해 결과를 다른 도구로 전송합니다.

## 지원되는 언어 및 프레임워크

Noir는 다양한 프로그래밍 언어와 프레임워크를 지원합니다:

*   **C#**: ASP.NET Core
*   **Crystal**: Kemal, Lucky
*   **Go**: Echo, Gin, Gorilla Mux, gRPC
*   **Java**: Armeria, JSP, Spring
*   **JavaScript**: Express, Koa
*   **Kotlin**: Spring
*   **PHP**: Pure PHP, Symfony
*   **Python**: Django, FastAPI, Flask
*   **Ruby**: Rails, Sinatra
*   **Rust**: Actix Web, Axum, Gotham, Rocket 등

전체 목록은 [지원되는 언어 및 프레임워크](/noir/usage/supported/language_and_frameworks) 페이지를 참조하세요.

## 주요 기능

### 엔드포인트 발견
Noir는 소스 코드에서 직접 API와 웹 엔드포인트를 추출하여 애플리케이션의 공격 표면에 대한 포괄적인 분석을 제공합니다.

### 매개변수 분석
엔드포인트와 함께 Noir는 쿼리 매개변수, 경로 매개변수, 헤더, 쿠키 및 요청 본문에서 매개변수를 식별합니다.

### 패시브 취약점 스캔
Noir에는 일반적인 보안 문제를 식별하기 위한 내장된 패시브 스캐너가 포함되어 있습니다.

### 다양한 출력 형식
결과는 JSON, YAML, OpenAPI 명세, cURL 명령 등 여러 형식으로 출력할 수 있습니다.

### 도구 통합
Noir는 ZAP, Burp Suite, Caido와 같은 인기 있는 보안 도구와 쉽게 통합됩니다.