+++
title = "CLI 앱"
description = "Noir가 CLI 애플리케이션의 커맨드라인 공격 표면(서브커맨드, 플래그, 위치 인자, 사용되는 환경 변수)을 21개 언어에 걸쳐 어떻게 매핑하는지 설명합니다."
weight = 7
sort_by = "weight"

+++

Noir는 웹 프레임워크와 API 명세뿐만 아니라 CLI 애플리케이션의 **커맨드라인 인터페이스**도 엔드포인트로 추출합니다. CLI 프로그램의 인자 파서 역시 공격 표면입니다. 외부에서 제공되는 플래그, 위치 인자, 환경 변수가 프로그램으로 흘러 들어가 셸, SQL 쿼리, 파일 경로, 네트워크 호출에 도달할 수 있습니다.

Noir는 각 (서브)커맨드를 엔드포인트로 모델링하고, 해당 커맨드가 받는 입력을 기록합니다.

## 엔드포인트 모델

CLI 진입점은 `method = "CLI"`, `protocol = "cli"`를 가진 엔드포인트입니다. URL은 커맨드를 가리킵니다:

| URL 형태 | 의미 |
|---|---|
| `cli://<binary>` | 루트 커맨드(서브커맨드 없이 실행되는 프로그램) |
| `cli://<binary>/<subcommand>` | 서브커맨드(`git commit`, `tool serve` 등) |

바이너리 이름은 프로젝트 매니페스트가 있으면 거기서 가져오며(`go.mod`, `Cargo.toml`, `package.json`의 `bin`/`name`, `*.csproj`, `argparse(prog=...)` 등), 없으면 소스 파일 / 디렉터리 이름으로 대체됩니다.

입력은 `param_type`으로 구분되는 파라미터입니다:

| param_type | 의미 | 예시 |
|---|---|---|
| `flag` | 이름이 있는 옵션 / 스위치 | `--port`, `-v`, `--config` |
| `argument` | 위치 인자 | `arg1`, `source`, `files` |
| `env` | 커맨드가 읽는 환경 변수 | `API_TOKEN`, `DATABASE_URL` |

기본 텍스트 출력에서는 `flags` / `arguments` / `env` 섹션으로 렌더링됩니다:

```
CLI cli://mytool/serve
  ○ flags: port, verbose
  ○ arguments: config
  ○ env: API_TOKEN
```

## 지원 언어 및 라이브러리

Noir는 각 언어의 내장 argv / flag / 환경 변수 메커니즘과 주요 CLI 라이브러리를 탐지합니다. 원시(raw) 환경 변수 읽기는 **게이팅**됩니다. 실제 CLI 진입점에 대해서만 노출되므로, 환경에서 설정을 읽는 웹 서버가 잘못된 `cli://` 엔드포인트를 남기지 않습니다.

| 언어 | 내장 | 라이브러리 |
|---|---|---|
| Go | `os.Args`, `flag`, `os.Getenv`/`LookupEnv` | cobra (+ viper env), urfave/cli, pflag, go-arg, go-flags |
| Python | `sys.argv`, `argparse`, `getopt`, `os.environ`/`getenv` | click, typer, fire, docopt |
| Rust | `std::env::args`/`var` | clap (derive), structopt, argh |
| JavaScript / TypeScript | `process.argv`, `util.parseArgs`, `Deno.args`, `Bun.argv`, `process.env` | commander, yargs, cac, meow, minimist |
| Ruby | `ARGV`, `OptionParser`, `ENV` | Thor, GLI, Slop, TTY::Option, commander |
| C# / F# | `Main(string[])`, `GetCommandLineArgs`, `GetEnvironmentVariable` | System.CommandLine, CommandLineParser, CliFx, Spectre.Console.Cli |
| Java | `main(String[])`, `System.getenv` | picocli, args4j, JCommander, commons-cli, airline |
| Kotlin | `main(Array<String>)`, `System.getenv` | clikt (+ envvar), kotlinx-cli |
| PHP | `$argv`, `getopt()`, `$_ENV`, `getenv()` | Symfony Console, CLImate, Minicli |
| C++ | `main(argc, argv)`, `getenv` | CLI11, getopt/getopt_long, cxxopts, boost::program_options, gflags |
| Swift | `CommandLine.arguments`, `ProcessInfo.environment` | swift-argument-parser |
| Crystal | `ARGV`, `OptionParser`, `ENV` | clim, admiral, commander |
| Elixir | `System.argv`, `OptionParser`, `System.get_env` | (표준 라이브러리) |
| Dart | `main(List<String>)`, `Platform.environment` | args (ArgParser / CommandRunner), dcli |
| Haskell | `getArgs`, `getEnv`/`lookupEnv` | optparse-applicative |
| Scala | `args`, `sys.env` | scopt, decline |
| Zig | `std.process.args`, `getEnvVarOwned` | zig-clap, zig-cli |
| Clojure | `*command-line-args*`, `System/getenv` | clojure.tools.cli, cli-matic |
| Lua | `arg`, `os.getenv` | argparse |
| Perl | `@ARGV`, `Getopt::Long`/`Getopt::Std`, `%ENV` | (표준 라이브러리) |
| Groovy | `args`, `System.getenv` | CliBuilder, picocli |

## 출력 동작

CLI 엔드포인트는 애플리케이션 표면의 일부이므로 구조화된 인벤토리 — JSON, JSONL, YAML, TOML, SARIF, Markdown, mermaid, HTML — 에 유지됩니다. 반면 HTTP 형태의 출력 및 전송 — cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, Postman, 능동 프로브 / 프록시 전송 — 에서는 **제외**됩니다. 커맨드 실행은 보내는 HTTP 요청이 아니기 때문입니다. HTTP 파라미터 취약점을 분류하는 HUNT 태거도 CLI 입력은 건너뜁니다.

## 참고 및 한계

* 탐지는 라인 스캔 기반(전체 파싱 아님)이므로, 깊게 중첩되었거나 메타프로그래밍이 많은 커맨드 트리는 부분적으로만 해석될 수 있습니다. 여러 파일에 흩어진 플래그, 인자, 환경 변수 읽기는 URL 기준으로 하나의 커맨드로 병합됩니다.
* 일부 빌더 스타일 API는 CLI 신호로 인식되지만 개별 인자까지 완전히 파싱되지는 않습니다(예: Rust의 clap 빌더 API). derive / 어노테이션 스타일은 완전히 파싱됩니다.
* 서브커맨드는 단일 레벨로 평탄화됩니다(`cli://tool/serve`). 더 깊은 중첩은 아직 모델링되지 않습니다.
