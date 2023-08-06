<div align="center">
  <img src="https://github.com/hahwul/noir/assets/13212227/d4e3d075-9cb0-4ca2-b577-958bfab6ca59" alt="" width="600px;">
  <p>♠️ Noir is an attack surface detector form source code.</p>
</div>

## Key Features
- Automatically identify language and framework from source code.
- Find API endpoints and web pages through code analysis.
- Load results quickly through interactions with proxy tools such as ZAP, Burpsuite, Caido and More Proxy tools.
- That provides structured data such as JSON and HAR for identified Attack Surfaces to enable seamless interaction with other tools. Also provides command line samples to easily integrate and collaborate with other tools, such as curls or httpie.

## Available Support Scope
### Endpoint's Entities
- Path
- Method
- Param
- Header
- Protocol (e.g ws)

### Languages and Frameworks

| Language | Framework | URL | Method | Param | Header | WS |
|----------|-----------|-----|--------|-------|--------|----|
| Go       | Echo      | ✅   | ✅      | X     | X      | X  |
| Python   | Django    | ✅   | X      | X     | X      | X  |
| Python   | Flask     | ✅   | X      | X     | X      | X  |
| Ruby     | Rails     | ✅   | ✅      | ✅     | X      | X  |
| Ruby     | Sinatra   | ✅   | ✅      | ✅     | X      | X  |
| Php      |           | ✅   | ✅      | ✅     | X      | X  |
| Java     | Spring    | ✅   | ✅      | X     | X      | X  |
| Java     | Jsp       | X   | X      | X     | X      | X  |
| Crystal  | Kemal     | ✅   | ✅      | ✅     | X      | ✅  |
| JS       | Express   | ✅   | ✅      | X     | X      | X  |
| JS       | Next      | X   | X      | X     | X      | X  |

## Installation
### Homebrew (macOS)
```bash
brew tap hahwul/noir
brew install noir
```

### From Sources
```bash
# Install Crystal-lang
# https://crystal-lang.org/install/

# Clone this repo
git clone https://github.com/hahwul/noir
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
docker pull ghcr.io/hahwul/noir:main
```

## Usage
```
Usage: noir <flags>
  Basic:
    -b PATH, --base-path ./app       (Required) Set base path
    -u URL, --url http://..          Set base url for endpoints
    -s SCOPE, --scope url,param      Set scope for detection

  Output:
    -f FORMAT, --format json         Set output format [plain/json/markdown-table/curl/httpie]
    -o PATH, --output out.txt        Write result to file
    --set-pvalue VALUE               Specifies the value of the identified parameter
    --no-color                       Disable color output
    --no-log                         Displaying only the results

  Deliver:
    --send-req                       Send the results to the web request
    --send-proxy http://proxy..      Send the results to the web request via http proxy

  Technologies:
    -t TECHS, --techs rails,php      Set technologies to use
    --techs-list                     Show all technologies

  Others:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    -h, --help                       Show help
```

![noir result preview](https://github.com/hahwul/noir/assets/13212227/1cde6445-eeae-492a-888b-59480aaf9a96)

### Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
