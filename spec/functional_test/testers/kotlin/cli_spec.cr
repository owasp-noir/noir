require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# clikt (CliktCommand root + subcommand, option/argument with envvar,
# System.getenv)
endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("config", "", "flag"),
    Param.new("TOOL_CONFIG", "", "env"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/cli_clikt/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests

# picocli (@Command root + subcommand, @Option/@Parameters, System.getenv)
picocli_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("config", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/cli_picocli/", {
  :techs     => 1,
  :endpoints => picocli_endpoints.size,
}, picocli_endpoints).perform_tests

# Regression: a wrapped multi-line @Command(...) must still open its own
# subcommand (not leak its flags onto the previous command), and an
# annotation-with-property on the same line (`@Option(...) var port: Int`)
# must resolve against that same-line property.
picocli_multiline_endpoints = [
  build.call("cli://multitool", [] of Param),
  build.call("cli://multitool/serve", [
    Param.new("port", "", "flag"),
    Param.new("target", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/cli_picocli_multiline/", {
  :techs     => 1,
  :endpoints => picocli_multiline_endpoints.size,
}, picocli_multiline_endpoints).perform_tests
