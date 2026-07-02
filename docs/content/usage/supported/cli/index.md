+++
title = "CLI Apps"
description = "How Noir maps the command-line attack surface of CLI applications — subcommands, flags, positional arguments, and consumed environment variables — across 21 languages."
weight = 7
sort_by = "weight"

+++

Beyond web frameworks and API specifications, Noir extracts the **command-line interface** of CLI applications as endpoints. A CLI program's argument parser is an attack surface too: externally supplied flags, positional arguments, and environment variables flow into the program and can reach a shell, an SQL query, a file path, or a network call.

Noir models each (sub)command as an endpoint and records the inputs that command accepts.

## Endpoint model

CLI entry points are endpoints with `method = "CLI"` and `protocol = "cli"`. The URL addresses the command:

| URL shape | meaning |
|---|---|
| `cli://<binary>` | the root command (the program invoked with no subcommand) |
| `cli://<binary>/<subcommand>` | a subcommand (`git commit`, `tool serve`, …) |

The binary name comes from the project manifest when one is present (`go.mod`, `Cargo.toml`, `package.json` `bin`/`name`, `*.csproj`, `argparse(prog=...)`, …); otherwise it falls back to the source file / directory name.

Inputs are parameters, distinguished by `param_type`:

| param_type | meaning | example |
|---|---|---|
| `flag` | a named option / switch | `--port`, `-v`, `--config` |
| `argument` | a positional argument | `arg1`, `source`, `files` |
| `env` | an environment variable the command reads | `API_TOKEN`, `DATABASE_URL` |

In plain output these render under `flags` / `arguments` / `env` sections:

```
CLI cli://mytool/serve
  ○ flags: port, verbose
  ○ arguments: config
  ○ env: API_TOKEN
```

## Supported languages and libraries

Noir detects the built-in argv / flag / environment mechanisms of each language plus its major CLI libraries. Raw environment reads are **gated**: they are only surfaced for genuine CLI entry points, so a web server that reads config from the environment does not leak spurious `cli://` endpoints.

| Language | Built-in | Libraries |
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
| Elixir | `System.argv`, `OptionParser`, `System.get_env` | (stdlib) |
| Dart | `main(List<String>)`, `Platform.environment` | args (ArgParser / CommandRunner), dcli |
| Haskell | `getArgs`, `getEnv`/`lookupEnv` | optparse-applicative |
| Scala | `args`, `sys.env` | scopt, decline |
| Zig | `std.process.args`, `getEnvVarOwned` | zig-clap, zig-cli |
| Clojure | `*command-line-args*`, `System/getenv` | clojure.tools.cli, cli-matic |
| Lua | `arg`, `os.getenv` | argparse |
| Perl | `@ARGV`, `Getopt::Long`/`Getopt::Std`, `%ENV` | (stdlib) |
| Groovy | `args`, `System.getenv` | CliBuilder, picocli |

## Output behavior

CLI endpoints stay in the structured inventory — JSON, JSONL, YAML, TOML, SARIF, Markdown, mermaid, HTML — because they are part of the application's surface. They are **excluded** from HTTP-shaped output and delivery — cURL, HTTPie, PowerShell, OpenAPI 2.0 / 3.0, Postman, and active probe / proxy delivery — because a command invocation is not an HTTP request you send. The HUNT tagger, which classifies HTTP parameter vulnerabilities, also skips CLI inputs.

## Notes and limitations

* Detection is line-scan based (no full parse), so deeply nested or heavily metaprogrammed command trees may be partially resolved. Flags, arguments, and env reads scattered across files are merged onto one command by URL.
* Some builder-style APIs are recognized as a CLI signal but not fully parsed into individual arguments (e.g. the clap builder API in Rust); the derive/annotation styles are parsed in full.
* Subcommands are flattened to a single level (`cli://tool/serve`); deeper nesting is not yet modeled.
