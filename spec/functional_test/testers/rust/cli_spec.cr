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

# --- getopts (flat builder API: optopt/optflag/reqopt + env) ---------------
getopts_endpoints = [
  build.call("cli://getoptsdemo", [
    Param.new("output", "", "flag"),
    Param.new("help", "", "flag"),
    Param.new("config", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/rust/cli_getopts/", {
  :techs     => 1,
  :endpoints => getopts_endpoints.size,
}, getopts_endpoints).perform_tests

# --- getopts FP: fully-qualified type annotation (`getopts::Options`) ------
# Regression for the reviewer finding: GETOPTS_NEW_RE previously required the
# bare word "Options" immediately after the colon in a type annotation, so
# `let mut opts: getopts::Options = getopts::Options::new();` (legitimate
# when a file only does `use getopts;` rather than `use getopts::Options;`)
# failed to bind the receiver and every subsequent opts.optopt/optflag/reqopt
# call was silently dropped (a false negative). The fixture also carries an
# unrelated `Options` struct of its own to prove the getopts receiver map
# doesn't cross-bind to it.
getopts_qualified_endpoints = [
  build.call("cli://getoptsqualdemo", [
    Param.new("output", "", "flag"),
    Param.new("help", "", "flag"),
    Param.new("config", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/rust/cli_getopts_fp/", {
  :techs     => 1,
  :endpoints => getopts_qualified_endpoints.size,
}, getopts_qualified_endpoints).perform_tests
