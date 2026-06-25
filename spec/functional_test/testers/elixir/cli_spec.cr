require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://mycli", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/elixir/cli_optionparser/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
