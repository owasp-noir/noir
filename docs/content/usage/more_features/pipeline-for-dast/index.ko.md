+++
title = "DAST 파이프라인에 Noir 통합하기"
description = "Noir를 동적 애플리케이션 보안 테스트(DAST) 파이프라인에 통합하는 방법을 알아보세요. 이 가이드는 ZAP 및 Burp Suite와 같은 프록시 도구와 함께 Noir를 사용하는 예제를 제공합니다."
weight = 12
sort_by = "weight"

[extra]
+++

동적 애플리케이션 보안 테스트(DAST)는 모든 보안 프로그램의 중요한 부분입니다. Noir를 DAST 파이프라인에 통합함으로써 보안 도구가 찾기 쉬운 엔드포인트뿐만 아니라 애플리케이션에 존재하는 모든 엔드포인트를 테스트하도록 할 수 있습니다.

## 프록시 도구와의 통합

Noir를 DAST 도구와 통합하는 가장 쉬운 방법 중 하나는 [OWASP ZAP](https://www.zaproxy.org/), [Burp Suite](https://portswigger.net/burp), 또는 [Caido](https://caido.io/)와 같은 프록시를 사용하는 것입니다. Noir의 `deliver` 기능을 사용하여 발견된 모든 엔드포인트를 프록시로 보낼 수 있으며, 그곳에서 DAST 도구로 스캔할 수 있습니다.

```bash
noir -b . -u http://localhost:3000 --send-proxy "http://localhost:8080"
```

이 명령은 다음과 같이 작동합니다:

1.  현재 디렉토리를 스캔합니다 (`-b .`).
2.  `http://localhost:3000`을 베이스로 사용하여 전체 URL을 구성합니다 (`-u`).
3.  발견된 모든 엔드포인트를 `http://localhost:8080`에서 실행 중인 프록시로 전송합니다 (`--send-proxy`).

이렇게 하면 프록시의 기록이 애플리케이션의 모든 엔드포인트로 채워져 쉽게 활성 스캔을 실행할 수 있습니다.

## ZAP 자동화와의 통합

더 자동화된 접근 방식을 위해 Noir를 사용하여 OpenAPI 명세를 생성한 다음 이를 ZAP의 자동화 프레임워크에 제공할 수 있습니다.

1.  **엔드포인트 발견**: 먼저 Noir를 사용하여 애플리케이션을 스캔하고 OpenAPI 명세를 생성합니다.

    ```bash
    noir -b ~/app_source -f oas3 --no-log -o doc.json
    ```

2.  **ZAP 스캔 실행**: 다음으로 ZAP 명령줄 스크립트를 사용하여 생성된 OpenAPI 파일을 사용한 자동화된 스캔을 실행합니다.

    ```bash
    ./zap.sh -openapifile ./doc.json \
        -openapitargeturl <TARGET> \
        -cmd -autorun zap.yaml <any other ZAP options>
    ```

이 2단계 프로세스를 통해 애플리케이션의 API를 완전히 커버하는 완전 자동화된 DAST 파이프라인을 만들 수 있습니다.

이 통합에 대한 자세한 내용은 ZAP 블로그 게시물을 확인하세요: [ZAP과 Noir로 DAST 강화하기](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/).
