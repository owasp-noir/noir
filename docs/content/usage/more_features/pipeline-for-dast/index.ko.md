+++
title = "DAST 파이프라인에 Noir 통합하기"
description = "ZAP, Burp Suite, Caido와 함께 Noir를 DAST 파이프라인에 통합합니다."
weight = 12
sort_by = "weight"

+++

Noir를 DAST 파이프라인에 통합하여 애플리케이션의 모든 엔드포인트를 테스트할 수 있습니다.

## 프록시 도구와의 통합

Noir의 `deliver` 기능으로 발견된 엔드포인트를 [OWASP ZAP](https://www.zaproxy.org/), [Burp Suite](https://portswigger.net/burp), [Caido](https://caido.io/) 등의 프록시로 전송합니다.

```bash
noir -b . -u http://localhost:3000 --send-proxy "http://localhost:8080"
```

현재 디렉터리를 스캔하고, `http://localhost:3000`을 기준 URL로 사용하여, 모든 엔드포인트를 `http://localhost:8080` 프록시로 전송합니다.

## ZAP 자동화와의 통합

Noir로 OpenAPI 명세를 생성한 후 ZAP 자동화 프레임워크에 전달합니다.

1.  **엔드포인트 발견**:

    ```bash
    noir -b ~/app_source -f oas3 --no-log -o doc.json
    ```

2.  **ZAP 스캔 실행**:

    ```bash
    ./zap.sh -openapifile ./doc.json \
        -openapitargeturl <TARGET> \
        -cmd -autorun zap.yaml <any other ZAP options>
    ```

자세한 내용은 ZAP 블로그 게시물을 참조하세요: [ZAP과 Noir로 DAST 강화하기](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/).
