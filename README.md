<div align="center">
  <img src="https://github.com/hahwul/noir/assets/13212227/d4e3d075-9cb0-4ca2-b577-958bfab6ca59" alt="" width="600px;">
  <p>♠️ Noir is an attack surface detector that identifies endpoints by static analysis.</p>
</div>

## Key Features
- Automatically identify language and framework from source code.
- Find API endpoints and web pages through code analysis.
- Load results quickly through interactions with proxy tools such as ZAP, Burpsuite, Caido and More Proxy tools.
- That provides structured data such as JSON and YAML for identified Attack Surfaces to enable seamless interaction with other tools. Also provides command line samples to easily integrate and collaborate with other tools, such as curls or httpie.

## Available Support Scope
### Endpoint's Entities
- Path
- Method
- Param
- Header
- Cookie
- Protocol (e.g ws)

### Languages and Frameworks

| Language | Framework   | URL | Method | Param | Header | Cookie | WS |
|----------|-------------|-----|--------|-------|--------|--------|----|
| Crystal  | Kemal       | ✅   | ✅    | ✅    | ✅     | ✅     | ✅ |
| Crystal  | Lucky       | ✅   | ✅    | ✅    | ✅     | ✅     |    |
| Go       | Echo        | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Go       | Gin         | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Python   | Django      | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Python   | Flask       | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Python   | FastAPI     | ✅   | ✅    | ✅    | ✅     | ✅     | ✅ |
| Ruby     | Rails       | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Ruby     | Sinatra     | ✅   | ✅    | ✅    | ✅     | ✅     | X  |
| Ruby     | Hanami      | ✅   | ✅    | X     | X      | X      | X  |
| Php      |             | ✅   | ✅    | ✅    | ✅     | X      | X  |
| Java     | Jsp         | ✅   | ✅    | ✅    | X      | X      | X  |
| Java     | Armeria     | ✅   | ✅    | X     | X      | X      | X  |
| Java     | Spring      | ✅   | ✅    | X     | X      | X      | X  |
| Kotlin   | Spring      | ✅   | ✅    | X     | X      | X      | X  |
| JS       | Express     | ✅   | ✅    | X     | X      | X      | X  |
| Rust     | Axum        | ✅   | ✅    | X     | X      | X      | X  |
| Elixir   | Phoenix     | ✅   | ✅    | X     | X      | X      | ✅ |
| C#       | ASP.NET MVC | ✅   | X     | X     | X      | X      | X  |
| JS       | Next        | X    | X     | X     | X      | X      | X  |


### Specification

| Specification          | Format  | URL | Method | Param | Header | WS |
|------------------------|---------|-----|--------|-------|--------|----|
| OAS 2.0 (Swagger 2.0)  | JSON    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 2.0 (Swagger 2.0)  | YAML    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 3.0                | JSON    | ✅  | ✅     | ✅    | ✅     | X  |
| OAS 3.0                | YAML    | ✅  | ✅     | ✅    | ✅     | X  |
| RAML                   | YAML    | ✅  | ✅     | ✅    | ✅     | X  |

## Installation
### Homebrew (macOS)
```bash
brew install noir

# https://formulae.brew.sh/formula/noir
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
```
Usage: noir <flags>
  Basic:
    -b PATH, --base-path ./app       (Required) Set base path
    -u URL, --url http://..          Set base url for endpoints
    -s SCOPE, --scope url,param      Set scope for detection

  Output:
    -f FORMAT, --format json         Set output format
                                     [plain/json/yaml/markdown-table/curl/httpie/oas2/oas3]
    -o PATH, --output out.txt        Write result to file
    --set-pvalue VALUE               Specifies the value of the identified parameter
    --no-color                       Disable color output
    --no-log                         Displaying only the results

  Deliver:
    --send-req                       Send the results to the web request
    --send-proxy http://proxy..      Send the results to the web request via http proxy
    --send-es https://es..           Send the results to elasticsearch
    --with-headers X-Header:Value    Add Custom Headers to be Used in Deliver
    --use-matchers string            Delivers URLs that match a specific condition
    --use-filters string             Excludes URLs that match a specific condition

  Technologies:
    -t TECHS, --techs rails,php      Set technologies to use
    --exclude-techs rails,php        Specify the technologies to be excluded
    --list-techs                     Show all technologies

  Others:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    -h, --help                       Show help
```

Example
```bash
noir -b . -u https://testapp.internal.domains
```

![](https://github.com/hahwul/noir/assets/13212227/68fb1b3a-dc57-4480-b8cf-e42f452e6706)

JSON Result
```
noir -b . -u https://testapp.internal.domains -f json
```
```json
[
  ...
  {
    "headers": [],
    "method": "POST",
    "params": [
      {
        "name": "article_slug",
        "param_type": "json",
        "value": ""
      },
      {
        "name": "title",
        "param_type": "json",
        "value": ""
      },
      {
        "name": "id",
        "param_type": "json",
        "value": ""
      }
    ],
    "protocol": "http",
    "url": "https://testapp.internal.domains/comments"
  }
]
```

### Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
