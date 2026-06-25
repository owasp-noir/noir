require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# swift-argument-parser (ParsableCommand root + subcommand, @Flag/@Option/@Argument)
endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/swift/cli_argumentparser/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests
