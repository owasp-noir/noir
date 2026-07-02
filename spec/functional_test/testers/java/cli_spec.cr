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

# jcommander (@Parameter names -> flags, name-less @Parameter -> main
# positional bound to the next field, @Parameters commandNames subcommand)
jcommander_endpoints = [
  build.call("cli://Tool", [
    Param.new("verbose", "", "flag"),
    Param.new("files", "", "argument"),
    Param.new("JC_TOKEN", "", "env"),
  ]),
  build.call("cli://Tool/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/java/cli_jcommander/", {
  :techs     => 1,
  :endpoints => jcommander_endpoints.size,
}, jcommander_endpoints).perform_tests
