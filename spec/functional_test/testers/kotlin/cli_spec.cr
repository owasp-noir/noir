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
