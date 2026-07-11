require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# System.CommandLine (RootCommand + Command + Option/Argument + env)
endpoints = [
  build.call("cli://sctool", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://sctool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/csharp/cli_systemcommandline/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests

# McMaster.Extensions.CommandLineUtils (attribute-driven: [Option]/[Argument]
# properties + [Command] subcommand + [Subcommand])
mcmaster_endpoints = [
  build.call("cli://mcmastertool", [
    Param.new("name", "", "flag"),
    Param.new("Input", "", "argument"),
    Param.new("MCM_TOKEN", "", "env"),
  ]),
  build.call("cli://mcmastertool/push", [
    Param.new("force", "", "flag"),
    Param.new("remote", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/csharp/cli_mcmaster/", {
  :techs     => 1,
  :endpoints => mcmaster_endpoints.size,
}, mcmaster_endpoints).perform_tests

# Cocona (minimal-API style: app.AddCommand("name", ([Option]/[Argument]
# params) => ...))
cocona_endpoints = [
  build.call("cli://coconatool", [
    Param.new("COCONA_TOKEN", "", "env"),
  ]),
  build.call("cli://coconatool/greet", [
    Param.new("name", "", "flag"),
    Param.new("message", "", "argument"),
  ]),
  build.call("cli://coconatool/bye", [] of Param),
]

FunctionalTester.new("fixtures/csharp/cli_cocona/", {
  :techs     => 1,
  :endpoints => cocona_endpoints.size,
}, cocona_endpoints).perform_tests

# Regression: several [Option]/[Argument] on ONE inline-lambda line must all
# surface (the old line.match captured only the first attribute per line).
cocona_multi_endpoints = [
  build.call("cli://coconamulti/run", [
    Param.new("name", "", "flag"),
    Param.new("count", "", "flag"),
    Param.new("target", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/csharp/cli_cocona_multi/", {
  :techs     => 1,
  :endpoints => cocona_multi_endpoints.size,
}, cocona_multi_endpoints).perform_tests

# Regression: `[Argument(0, Description = "free text")]` must resolve to the
# annotated property name, not grab the space-containing description string.
mcmaster_desc_endpoints = [
  build.call("cli://mcmdesc", [
    Param.new("Remote", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/csharp/cli_mcmaster_desc/", {
  :techs     => 1,
  :endpoints => mcmaster_desc_endpoints.size,
}, mcmaster_desc_endpoints).perform_tests
