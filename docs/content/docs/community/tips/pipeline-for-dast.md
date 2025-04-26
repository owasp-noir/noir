---
title: Pipeline for DAST
description: "Guide to integrating Noir into Dynamic Application Security Testing (DAST) pipelines with proxy tools and ZAP"
---

## DAST (Dynamic Application Security Testing)

DAST is a type of security testing that analyzes a running application to identify vulnerabilities. It simulates attacks from an external perspective to find security issues in the application.

## Proxy Tool Integration

This command automates the use of a proxy tool in a security testing pipeline. noir is used with the `-b` option to specify the base directory (.) and -u to target a local application (http://localhost.hahwul.com:3000). The --send-proxy parameter directs traffic to a proxy server running on http://localhost:8090. This setup allows for monitoring and intercepting HTTP requests through tools like ZAP, Caido, or Burp Suite during the testing process.

```bash
noir -b . -u http://localhost.hahwul.com:3000 --send-proxy "http://localhost:8090"
```

## ZAP Integration

The process begins with endpoint discovery using noir, which scans the application source code in the specified directory (~/app_source), generates an OpenAPI specification (doc.json), and saves it in JSON format.

Next, the doc.json file is used in an automated ZAP scan. The zap.sh script, with the `-openapifile` option, loads the generated endpoints and uses `-openapitargeturl` to specify the target URL for testing. The `-cmd` and `-autorun` options allow for automated execution of ZAP commands based on zap.yaml, along with any additional configuration parameters. This setup enables comprehensive vulnerability assessment across discovered endpoints in the target application.

```bash
# Discovering endpoints
noir -b ~/app_source -f oas3 --no-log -o doc.json

# Automation scan with endpoints
./zap.sh -openapifile ./doc.json \
    -openapitargeturl <TARGET> \
    -cmd -autorun zap.yaml <any other ZAP options>
```

For further details on integrating Noir and ZAP for enhanced DAST capabilities, refer to the [Powering Up DAST with ZAP and Noir](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/) ZAP blog post.