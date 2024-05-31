<div align="center">
  <img src="https://github.com/noir-cr/noir/assets/13212227/8c4470fe-c8f4-4060-9f12-b038ad211913" alt="" width="500px;">
  <p>Attack surface detector that identifies endpoints by static analysis.</p>
</div>

<p align="center">
<a href="https://github.com/noir-cr/noir/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/noir-cr/noir/releases">
<img src="https://img.shields.io/github/v/release/noir-cr/noir?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#available-support-scope">Available Support Scope</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a>
</p>

## Key Features
- Automatically identify language and framework from source code.
- Find API endpoints and web pages through code analysis.
- Load results quickly through interactions with proxy tools such as ZAP, Burpsuite, Caido and More Proxy tools.
- That provides structured data such as JSON and YAML for identified Attack Surfaces to enable seamless interaction with other tools. Also provides command line samples to easily integrate and collaborate with other tools, such as curls or httpie.

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
git clone https://github.com/noir-cr/noir
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
docker pull ghcr.io/noir-cr/noir:main
```

## Usage
```bash
noir -h 
```

```
USAGE: noir <flags>

FLAGS:
  BASE:
    -b PATH, --base-path ./app       (Required) Set base path
    -u URL, --url http://..          Set base url for endpoints

  OUTPUT:
    -f FORMAT, --format json         Set output format
                                       * plain yaml json jsonl markdown-table
                                       * curl httpie oas2 oas3
                                       * only-url only-param only-header only-cookie
    -o PATH, --output out.txt        Write result to file
    --set-pvalue VALUE               Specifies the value of the identified parameter
    --include-path                   Include file path in the plain result
    --no-color                       Disable color output
    --no-log                         Displaying only the results

  TAGGER:
    -T, --use-all-taggers            Activates all taggers for full analysis coverage
    --use-taggers VALUES             Activates specific taggers (e.g., --use-taggers hunt,oauth)
    --list-taggers                   Lists all available taggers

  DELIVER:
    --send-req                       Send results to a web request
    --send-proxy http://proxy..      Send results to a web request via an HTTP proxy
    --send-es http://es..            Send results to Elasticsearch
    --with-headers X-Header:Value    Add custom headers to be included in the delivery
    --use-matchers string            Send URLs that match specific conditions to the Deliver
    --use-filters string             Exclude URLs that match specified conditions and send the rest to Deliver

  DIFF:
    --diff-path ./app2               Specify the path to the old version of the source code for comparison

  TECHNOLOGIES:
    -t TECHS, --techs rails,php      Specify the technologies to use
    --exclude-techs rails,php        Specify the technologies to be excluded
    --list-techs                     Show all technologies

  CONFIG:
    --config-file ./config.yaml      Specify the path to a configuration file in YAML format
    --concurrency 100                Set concurrency
    --generate-zsh-completion        Generate Zsh completion script

  DEBUG:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    --build-info                     Show version and Build info

  OTHERS:
    -h, --help                       Show help
```

Example
```bash
noir -b . -u https://testapp.internal.domains -T
```

![](https://github.com/noir-cr/noir/assets/13212227/4e69da04-d585-4745-9cc7-ef6e69e193b0)

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

## Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
