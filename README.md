<div align="center">
  <img src="https://github.com/hahwul/noir/assets/13212227/d4e3d075-9cb0-4ca2-b577-958bfab6ca59" alt="" width="600px;">
  <p>♠️ Noir is an attack surface detector form source code.</p>
</div>

## Key Features
- Automatically identify language and framework from source code.
- Find API endpoints and web pages through code analysis.
- Load results quickly through interactions with proxy tools such as ZAP, Burpsuite, Caido and More Proxy tools.
- That provides structured data such as JSON and HAR for identified Attack Surfaces to enable seamless interaction with other tools. Also provides command line samples to easily integrate and collaborate with other tools, such as curls or httpie.

## Support
### Language and Framework
| Language | Framework | Tech Detect | URL | Param | Header |
|----------|-----------|-------------|-----|-------|--------|
| Go       | Echo      |      ✅     |  ✅ | X     | X      |
| Python   | Django    |      ✅     |  X  | X     | X      |
| Python   | Flask     |      ✅     |  ✅ | X     | X      |
| Ruby     | Rails     |      ✅     |  ✅ | ✅    | X      |
| Ruby     | Sinatra   |      ✅     |  ✅ | X     | X      |
| Php      |           |      ✅     |  ✅ | ✅    | X      |
| Java     | Spring    |      ✅     |  ✅ | X     | X      |
| Java     | Jsp       |      ✅     |  X  | X     | X      |
| JS       | Express   |      ✅     |  🟧  | X     | X      |
| JS       | Next      |      X      |  X  | X     | X      |

## Installation
```bash
git clone https://github.com/hahwul/noir
cd noir
shards install
shards build
cp ./bin/noir /usr/bin/

# I'll support homebrew when noir is officially released.
```

## Usage
```
Usage: noir <flags>
  Basic:
    -b PATH, --base-path ./app       (Required) Set base path
    -u URL, --url http://..          Set base url for endpoints

  Output:
    -f FORMAT, --format json         Set output format [plain/json/curl/httpie]
    -o PATH, --output out.txt        Write result to file

  Technologies:
    -t TECHS, --techs rails,php      Set technologies to use
    --techs-list                     Show all technologies

  Others:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    -h, --help                       Show help
```

### Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
