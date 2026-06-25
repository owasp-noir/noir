require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("name", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [Param.new("port", "", "flag")]),
]
FunctionalTester.new("fixtures/dart/cli_args/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
