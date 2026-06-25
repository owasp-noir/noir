require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# CLI11 (App + add_flag + add_subcommand + add_option, std::getenv)
endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/cpp/cli_cli11/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests
