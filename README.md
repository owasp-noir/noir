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
  <a href="#installation">Installation</a> •
  <a href="https://owasp-noir.github.io/noir/">Documentation</a> •
  <a href="#available-support-scope">Available Support Scope</a> •
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a>
</p>

## Key Features

- Identify API endpoints and parameters from source code.
- Support various source code languages and frameworks.
- Provide analysts with technical information and security issues identified during source code analysis.
- Friendly pipeline & DevOps integration, offering multiple output formats (JSON, YAML, OAS spec) and compatibility with tools like curl and httpie.
- Friendly Offensive Security Tools integration, allowing usage with tools such as ZAP and Caido, Burpsuite.
- Generate elegant and clear output results.

## Available Support Scope

<details>
  <summary>Endpoint's Entities</summary>

- Path
- Method
- Param
- Header
- Cookie
- Protocol (e.g ws)
- Details (e.g The origin of the endpoint)

</details>

<details>
  <summary>Languages and Frameworks</summary>

| Language | Framework   | URL | Method | Param | Header | Cookie | WS |
|----------|-------------|-----|--------|-------|--------|--------|----|
| Crystal  | Kemal       | ✅   | ✅    | ✅    | ✅     | ✅     | ✅ |
| Crystal  | Lucky       | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Go       | Beego       | ✅   | ✅    | X     | X      | X      | X  |
| Go       | Echo        | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Go       | Gin         | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Go       | Fiber       | ✅   | ✅    | ✅    | ✅     | ✅     | ✅ |
| Python   | Django      | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Python   | Flask       | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Python   | FastAPI     | ✅   | ✅    | ✅    | ✅     | ✅     | ✅ |
| Ruby     | Rails       | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Ruby     | Sinatra     | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Ruby     | Hanami      | ✅   | ✅    | X     | X      | X      | X  |
| Php      |             | ✅   | ✅    | ✅    | ✅     | X      | X  |
| Java     | Jsp         | ✅   | ✅    | ✅    | X      | X      | X  |
| Java     | Armeria     | ✅   | ✅    | X     | X      | X      | X  |
| Java     | Spring      | ✅   | ✅    | ✅    | ✅     | X      | X  |
| Kotlin   | Spring      | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| JS       | Express     | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| JS       | Restify     | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Rust     | Axum        | ✅   | ✅    | X     | X      | X      | X  |
| Rust     | Rocket      | ✅   | ✅    | X     | X      | X      | X  |
| Elixir   | Phoenix     | ✅   | ✅    | X     | X      | X      | ✅ |
| C#       | ASP.NET MVC | ✅   | X     | X     | X      | X      | X  |
| JS       | Next        | X    | X     | X     | X      | X      | X  |

</details>

<details>
  <summary>Specification</summary>

| Specification          | Format  | URL | Method | Param | Header | WS |
|------------------------|---------|-----|--------|-------|--------|----|
| OAS 2.0 (Swagger 2.0)  | JSON    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 2.0 (Swagger 2.0)  | YAML    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 3.0                | JSON    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 3.0                | YAML    | ✅  | ✅     | ✅    | ✅     | X  |
| RAML                   | YAML    | ✅  | ✅     | ✅    | ✅     | X  |
| HAR                    | JSON    | ✅  | ✅     | ✅    | ✅     | X  |

</details>

## Installation
### Homebrew

```bash
brew install noir

# https://formulae.brew.sh/formula/noir
```

### Snapcraft

```bash
sudo snap install noir

# https://snapcraft.io/noir
```

### From Sources
```bash
# Install Crystal-lang
# https://crystal-lang.org/install/

# Clone this repo
git clone https://github.com/owasp-noir/noir
cd noir

# Install Dependencies
shards install

# Build
shards build --release --no-debug

# Copy binary
cp ./bin/noir /usr/bin/
```

### Docker (GHCR)
```bash
docker pull ghcr.io/owasp-noir/noir:main
```

## Usage

```bash
noir -h 
```

Example
```bash
noir -b . -u https://testapp.internal.domains -T
```

![](https://github.com/owasp-noir/noir/assets/13212227/4e69da04-d585-4745-9cc7-ef6e69e193b0)

JSON Result
```
noir -b . -u https://testapp.internal.domains -f json -T
```

```json
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
```

For more details, please visit our [documentation](https://owasp-noir.github.io/noir/) page.

## Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
