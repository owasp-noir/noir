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
