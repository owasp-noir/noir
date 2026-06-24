require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so
# build via a Proc that mutates a local and returns it.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- Thor (desc + method_option/option + def subcommands; top-level ENV) ----
thor_endpoints = [
  build.call("cli://thor_app", [
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://thor_app/serve", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://thor_app/build", [] of Param),
]

FunctionalTester.new("fixtures/ruby/cli_thor/", {
  :techs     => 1,
  :endpoints => thor_endpoints.size,
}, thor_endpoints).perform_tests

# --- OptionParser (opts.on long flags + ENV) -------------------------------
optparse_endpoints = [
  build.call("cli://optparser", [
    Param.new("verbose", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("DATABASE_URL", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/ruby/cli_optparse/", {
  :techs     => 1,
  :endpoints => optparse_endpoints.size,
}, optparse_endpoints).perform_tests
