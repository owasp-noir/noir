+++
title = "Integrating Noir into Your DAST Pipeline"
description = "Learn how to integrate Noir into your Dynamic Application Security Testing (DAST) pipeline. This guide provides examples of how to use Noir with proxy tools like ZAP and Burp Suite."
weight = 4
sort_by = "weight"

[extra]
+++

Dynamic Application Security Testing (DAST) is a crucial part of any security program. By integrating Noir into your DAST pipeline, you can ensure that your security tools are testing all of the endpoints that exist in your application, not just the ones that are easy to find.

## Integrating with a Proxy Tool

One of the easiest ways to integrate Noir with a DAST tool is to use a proxy like [OWASP ZAP](https://www.zaproxy.org/), [Burp Suite](https://portswigger.net/burp), or [Caido](https://caido.io/). You can use Noir's `deliver` feature to send all of the discovered endpoints to your proxy, where they can then be scanned by your DAST tool.

```bash
noir -b . -u http://localhost:3000 --send-proxy "http://localhost:8080"
```

This command will:

1.  Scan the current directory (`-b .`).
2.  Construct full URLs using `http://localhost:3000` as the base (`-u`).
3.  Send all of the discovered endpoints to the proxy running on `http://localhost:8080` (`--send-proxy`).

This will populate your proxy's history with all of the endpoints from your application, allowing you to easily run an active scan on them.

## Integrating with ZAP Automation

For a more automated approach, you can use Noir to generate an OpenAPI specification and then feed that into ZAP's automation framework.

1.  **Discover Endpoints**: First, use Noir to scan your application and generate an OpenAPI specification.

    ```bash
    noir -b ~/app_source -f oas3 --no-log -o doc.json
    ```

2.  **Run ZAP Scan**: Next, use the ZAP command-line script to run an automated scan using the generated OpenAPI file.

    ```bash
    ./zap.sh -openapifile ./doc.json \
        -openapitargeturl <TARGET> \
        -cmd -autorun zap.yaml <any other ZAP options>
    ```

This two-step process allows you to create a fully automated DAST pipeline that ensures complete coverage of your application's API.

For more details on this integration, check out the ZAP blog post: [Powering Up DAST with ZAP and Noir](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/).

