require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# picocli (@Command root + subcommand, @Option, @Parameters, System.getenv)
endpoints = [
  build.call("cli://app", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://app/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/java/cli_picocli/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests
