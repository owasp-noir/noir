require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so
# build via a Proc that mutates a local and returns it.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- clap (derive: Parser root args + Subcommand variants + env) -----------
clap_endpoints = [
  build.call("cli://clapdemo", [
    Param.new("verbose", "", "flag"),
    Param.new("APP_VERBOSE", "", "env"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://clapdemo/serve", [
    Param.new("port", "", "flag"),
    Param.new("PORT", "", "env"),
  ]),
  build.call("cli://clapdemo/build", [
    Param.new("target", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/rust/cli_clap/", {
  :techs     => 1,
  :endpoints => clap_endpoints.size,
}, clap_endpoints).perform_tests
