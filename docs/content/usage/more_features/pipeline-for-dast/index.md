+++
title = "Integrating Noir into Your DAST Pipeline"
description = "Integrate Noir into your DAST pipeline with ZAP, Burp Suite, or Caido."
weight = 12
sort_by = "weight"

+++

Integrate Noir into your DAST pipeline to ensure security tools test all application endpoints.

## Integrating with a Proxy Tool

Use Noir's `deliver` feature to send discovered endpoints to a proxy like [OWASP ZAP](https://www.zaproxy.org/), [Burp Suite](https://portswigger.net/burp), or [Caido](https://caido.io/).

```bash
noir -b . -u http://localhost:3000 --send-proxy "http://localhost:8080"
```

This scans the current directory, constructs URLs using `http://localhost:3000` as the base, and sends all endpoints to the proxy at `http://localhost:8080`.

## Integrating with ZAP Automation

Generate an OpenAPI specification with Noir and feed it into ZAP's automation framework.

1.  **Discover Endpoints**:

    ```bash
    noir -b ~/app_source -f oas3 --no-log -o doc.json
    ```

2.  **Run ZAP Scan**:

    ```bash
    ./zap.sh -openapifile ./doc.json \
        -openapitargeturl <TARGET> \
        -cmd -autorun zap.yaml <any other ZAP options>
    ```

For more details, see the ZAP blog post: [Powering Up DAST with ZAP and Noir](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/).
