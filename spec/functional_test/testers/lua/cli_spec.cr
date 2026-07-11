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

cliargs_endpoints = [
  build.call("cli://mytool", [
    Param.new("INPUT", "", "argument"),
    Param.new("output", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/lua/cli_cliargs/", {:techs => 1, :endpoints => cliargs_endpoints.size}, cliargs_endpoints).perform_tests

# Regression: an unrelated `logger:set_name(...)` and `menu:add_option/add_flag(...)`
# whose receivers were never bound to require("cliargs") must not leak into
# the cli:// endpoint's URL or params (attribution false positives).
cliargs_fp_endpoints = [
  build.call("cli://app", [
    Param.new("INPUT", "", "argument"),
    Param.new("output", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/lua/cli_cliargs_fp/", {:techs => 1, :endpoints => cliargs_fp_endpoints.size}, cliargs_fp_endpoints).perform_tests
