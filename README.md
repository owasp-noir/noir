# Noir
Discover all API and web page in the source code

> Developing now.. 🚧

## Key Features
- Automatically identify language and framework from source code.
- Find API endpoints and web pages through code analysis.
- Load results quickly through interactions with proxy tools such as ZAP, Burpsuite, Caido and More Proxy tools.
- It is possible to interact with other tools by providing structured data such as JSON and HAR for the results. (pipeline)

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
| Node JS  | Pure      |      X      |  X  | X     | X      |
| Node JS  | Express   |      X      |  X  | X     | X      |
| Node JS  | Next      |      X      |  X  | X     | X      |

### Output Format
- Plain (default/`--format plain`)
- JSON (`--format json`)
- [Curl](https://github.com/curl/curl) (`--format curl`)
- [Httpie](https://github.com/httpie/httpie) (`--format httpie`)

### Contributing
Noir is open-source project and made it with ❤️ 
if you want contribute this project, please see [CONTRIBUTING.md](./CONTRIBUTING.md) and Pull-Request with cool your contents.

![](./CONTRIBUTORS.svg)
