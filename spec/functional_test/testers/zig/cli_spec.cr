require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("help", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("file", "", "argument"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_clap/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
