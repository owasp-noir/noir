require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_tools/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
