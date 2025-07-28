<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/owasp-noir/noir/assets/13212227/0577860e-3d7e-4294-8f1f-dc7b87ce2b2b" width="500px;">
    <img alt="OWASP Noir Logo" src="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
  </picture>
  <p>정적 분석을 통해 엔드포인트를 식별하는 공격 표면 탐지기입니다.</p>
</div>

<p align="center">
<a href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/owasp-noir/noir/releases">
<img src="https://img.shields.io/github/v/release/owasp-noir/noir?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
<a href="https://owasp.org/www-project-noir/">
<img src="https://img.shields.io/badge/OWASP-000000?style=for-the-badge&logo=owasp&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://owasp-noir.github.io/noir/">문서</a> •
  <a href="https://owasp-noir.github.io/noir/get_started/installation/">설치</a> •
  <a href="https://owasp-noir.github.io/noir/supported">지원 범위</a> •
  <a href="#usage">사용법</a> •
  <a href="#contributing">기여</a>
</p>

OWASP Noir는 화이트박스 보안 테스트 및 보안 파이프라인 강화를 위한 공격 표면 식별을 전문으로 하는 오픈 소스 프로젝트입니다. 여기에는 철저한 보안 분석을 위해 소스 코드 내에서 API 엔드포인트, 웹 엔드포인트 및 기타 잠재적 진입점을 발견하는 기능이 포함됩니다.

## 주요 기능

- 소스 코드에서 API 엔드포인트 및 매개변수 추출
- 여러 언어 및 프레임워크 지원
- 상세한 분석 및 규칙 기반 수동 스캔으로 보안 문제 발견
- curl, ZAP, Caido와 같은 DevOps 파이프라인 및 도구와 원활하게 통합
- JSON, YAML, OAS와 같은 형식으로 명확하고 실행 가능한 결과 제공
- 익숙하지 않은 프레임워크 및 숨겨진 API에 대한 AI를 통한 엔드포인트 검색 향상

## 사용법

```bash
noir -h
```

예시
```bash
noir -b <source_dir>
```

![](/docs/assets/images/get_started/basic.png)

JSON 결과
```
noir -b . -u https://testapp.internal.domains -f json -T
```

```json
{
  "endpoints": [
    {
      "url": "https://testapp.internal.domains/query",
      "method": "POST",
      "params": [
        {
          "name": "my_auth",
          "value": "",
          "param_type": "cookie",
          "tags": []
        },
        {
          "name": "query",
          "value": "",
          "param_type": "form",
          "tags": [
            {
              "name": "sqli",
              "description": "이 매개변수는 SQL 삽입 공격에 취약할 수 있습니다.",
              "tagger": "Hunt"
            }
          ]
        }
      ],
      "details": {
        "code_paths": [
          {
            "path": "spec/functional_test/fixtures/crystal_kemal/src/testapp.cr",
            "line": 8
          }
        ]
      },
      "protocol": "http",
      "tags": []
    }
  ]
}
```

자세한 내용은 [문서](https://owasp-noir.github.io/noir/) 페이지를 참조하십시오.

## 로드맵
지원되는 프로그래밍 언어와 프레임워크의 범위를 확장하고 정확성을 지속적으로 높일 계획입니다. 또한 AI와 대규모 언어 모델(LLM)을 활용하여 분석 기능을 크게 확장할 것입니다.

처음에는 화이트박스 테스트를 지원하는 도구로 구상되었지만, 우리의 즉각적인 목표는 DevSecOps 파이프라인 내에서 소스 코드의 엔드포인트를 추출하여 제공하는 것입니다. 이를 통해 동적 애플리케이션 보안 테스트(DAST) 도구가 더 정확하고 안정적인 스캔을 수행할 수 있습니다.

앞으로 우리의 목표는 우리 도구가 소스 코드와 DAST 및 기타 보안 테스트 도구를 원활하게 연결하는 중요한 다리 역할을 하여 보다 통합되고 효과적인 보안 태세를 촉진하는 것입니다.

## 기여

Noir는 오픈 소스 프로젝트이며 ❤️로 만들어졌습니다.
이 프로젝트에 기여하고 싶다면 [CONTRIBUTING.md](./CONTRIBUTING.md)를 참조하고 멋진 콘텐츠로 Pull-Request를 보내주세요.

[![](./CONTRIBUTORS.svg)](https://github.com/owasp-noir/noir/graphs/contributors)

*PassiveScan 규칙 기여자*

[![](https://raw.githubusercontent.com/owasp-noir/noir-passive-rules/refs/heads/main/CONTRIBUTORS.svg)](https://github.com/owasp-noir/noir-passive-rules/graphs/contributors)
