<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/owasp-noir/noir/assets/13212227/0577860e-3d7e-4294-8f1f-dc7b87ce2b2b" width="500px;">
    <img alt="OWASP Noir Logo" src="https://github.com/owasp-noir/noir/assets/13212227/04aee7d0-c224-481b-8d79-2dbdcf3ad84b" width="500px;">
  </picture>
  <p>Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface.</p>
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
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a> •
  <a href="./CHANGELOG.md">Changelog</a>
</p>

Noir reads source code and extracts every endpoint your application exposes — shadow APIs, deprecated routes, and hidden surfaces included.

That inventory drives two downstream stacks. ZAP, Burp Suite, and Caido pick up endpoints they would never have crawled on their own. AI SAST — LLM-based code auditors and security agents — gets the entrypoints, files, parameters, and tags it needs to review attacker-reachable code, instead of skimming the whole repository.

## Why Noir?

- Attack Surface Discovery: Analyzes source code to identify your application's complete attack surface, including hidden endpoints, shadow APIs, and other security blind spots.
- AI-Powered Analysis: Leverages Large Language Models (LLMs) to detect endpoints in any language or framework — even those not natively supported.
- Feeds DAST & AI SAST: One endpoint inventory drives ZAP, Burp Suite, and Caido on the dynamic side, and points LLM-based SAST and code auditors at the entrypoints, files, and parameters worth reviewing on the static side.
- DevSecOps Ready: Designed for seamless integration into security pipelines with support for tools like ZAP, Burp Suite, Caido, and more.
- Multi-Format Output: Delivers results in JSON, YAML, TOML, OpenAPI Specification, SARIF, and other formats for easy integration with your existing workflow.

## Usage

```bash
noir -h
```

Example
```bash
noir -b <source_dir>
```

If you use it with Github Action, please refer to this [document](/github-action) .

![](/docs/content/get_started/overview/noir-usage.jpg)

For more details, please visit our [documentation](https://owasp-noir.github.io/noir/) page.

## Roadmap
We plan to expand the range of supported programming languages and frameworks, and to continuously increase accuracy. Furthermore, we will leverage AI and Large Language Models (LLMs) to significantly broaden our analysis capabilities.

Initially conceived as a tool to assist with WhiteBox testing, our immediate goal remains to extract and provide endpoints from the source code within the DevSecOps Pipeline. This enables Dynamic Application Security Testing (DAST) tools to conduct more accurate and stable scans.

Looking ahead, our ambition is for Noir to become the canonical attack-surface layer for application security — the single inventory that DAST tools and AI SAST share, so every downstream consumer starts from the same view of what is actually exposed.

## News & Updates

* August 2025: Presented at the OWASP Seoul Meetup. ([Open Source Gardening](https://owasp-noir.github.io/noir/community/media/#featured-owasp-seoul-aug-2025-open-source-gardening))
* November 2024: Published a guest blog post ["Powering Up DAST with ZAP and Noir"](https://www.zaproxy.org/blog/2024-11-11-powering-up-dast-with-zap-and-noir/) on the ZAP blog.
* June 2024: Joined OWASP as OWASP Noir
  * Renamed the GitHub organization from noir-cr to owasp-noir
  * Transitioned to co-leadership with [@ksg97031](https://github.com/ksg97031)
* November 2023: Moved the Noir repository to the noir-cr GitHub organization.
* August 2023: Started as [@hahwul](https://github.com/hahwul)'s personal project.

## Contributing

Noir is an open-source project made with ❤️.
If you would like to contribute, please check [CONTRIBUTING.md](./CONTRIBUTING.md) and submit a Pull Request.

[![](./docs/static/CONTRIBUTORS.svg)](https://github.com/owasp-noir/noir/graphs/contributors)

## Mascot

| ![](docs/static/images/mascot/hak-hi.webp "Hak") | Our mascot is Hak (학), a crane symbolizing elegance and precision in spotting hidden flaws. In Korean, "학" means "crane," representing a sharp ally who dives deep to uncover vulnerabilities and attack surfaces in your code. <br><br> For more artwork and resources related to Hak, check out [noir-artwork repository](https://github.com/owasp-noir/noir-artwork).|
| -------------- | -------------- |
