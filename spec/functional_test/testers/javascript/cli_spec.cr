require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so
# build via a Proc that mutates a local and returns it.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- commander (program/command + option/argument + process.env) -----------
commander_endpoints = [
  build.call("cli://commanderdemo", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://commanderdemo/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_commander/", {
  :techs     => 1,
  :endpoints => commander_endpoints.size,
}, commander_endpoints).perform_tests

# --- yargs (option + command + positional) ---------------------------------
yargs_endpoints = [
  build.call("cli://yargsdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://yargsdemo/serve", [
    Param.new("port", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_yargs/", {
  :techs     => 1,
  :endpoints => yargs_endpoints.size,
}, yargs_endpoints).perform_tests
