require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
    Param.new("arg1", "", "argument"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("host", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]
FunctionalTester.new("fixtures/lua/cli_argparse/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
