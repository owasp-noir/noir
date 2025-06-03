<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/owasp-noir/noir/assets/13212227/0577860e-3d7e-4294-8f1f-dc7b87ce2b2b" width="500px;">
    <img alt="OWASP Noir Logo" src="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
  </picture>
  <p>Attack surface detector that identifies endpoints by static analysis.</p>
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
  <a href="https://owasp-noir.github.io/noir/">Documentation</a> •
  <a href="https://owasp-noir.github.io/noir/get_started/installation/">Installation</a> •
  <a href="https://owasp-noir.github.io/noir/supported">Available Support Scope</a> •
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a>
</p>

OWASP Noir is an open-source project specializing in identifying attack surfaces for enhanced whitebox security testing and security pipeline. This includes the capability to discover API endpoints, web endpoints, and other potential entry points within source code for thorough security analysis.

## Key Features

- Extract API endpoints and parameters from source code.
- Support multiple languages and frameworks.
- Uncover security issues with detailed analysis and rule-based passive scanning.
- Integrate seamlessly with DevOps pipelines and tools like curl, ZAP, and Caido.
- Deliver clear, actionable results in formats like JSON, YAML, and OAS.
- Enhance endpoint discovery with AI for unfamiliar frameworks and hidden APIs.

## Usage

```bash
noir -h 
```

Example
```bash
noir -b <source_dir>
```

![](/docs/assets/images/get_started/basic.png)

JSON Result
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
              "description": "This parameter may be vulnerable to SQL Injection attacks.",
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

For more details, please visit our [documentation](https://owasp-noir.github.io/noir/) page.

## Road Map
We plan to expand the range of supported programming languages and frameworks, and to continuously increase accuracy. Furthermore, we will leverage AI and Large Language Models (LLMs) to significantly broaden our analysis capabilities.

Initially conceived as a tool to assist with WhiteBox testing, our immediate goal remains to extract and provide endpoints from the source code within the DevSecOps Pipeline. This enables Dynamic Application Security Testing (DAST) tools to conduct more accurate and stable scans.

Looking ahead, our ambition is for our tool to evolve into a crucial bridge, seamlessly connecting source code with DAST and other security testing tools, thereby facilitating a more integrated and effective security posture.

## Contributing

Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

[![](./CONTRIBUTORS.svg)](https://github.com/owasp-noir/noir/graphs/contributors)

*PassiveScan Rule contributors*

[![](https://raw.githubusercontent.com/owasp-noir/noir-passive-rules/refs/heads/main/CONTRIBUTORS.svg)](https://github.com/owasp-noir/noir-passive-rules/graphs/contributors)
