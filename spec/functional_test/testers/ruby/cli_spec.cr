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

# --- Optimist (flat `opt` declarations + ENV) ------------------------------
optimist_endpoints = [
  build.call("cli://optimist_app", [
    Param.new("name", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("OPTIMIST_API_KEY", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/ruby/cli_optimist/", {
  :techs     => 1,
  :endpoints => optimist_endpoints.size,
}, optimist_endpoints).perform_tests

# --- Clamp (option/parameter + nested subcommand block + ENV) -------------
clamp_endpoints = [
  build.call("cli://clamp_app", [
    Param.new("verbose", "", "flag"),
    Param.new("file", "", "argument"),
    Param.new("CLAMP_TOKEN", "", "env"),
  ]),
  build.call("cli://clamp_app/serve", [
    Param.new("port", "", "flag"),
  ]),
]

clamp_tester = FunctionalTester.new("fixtures/ruby/cli_clamp/", {
  :techs     => 1,
  :endpoints => clamp_endpoints.size,
}, clamp_endpoints)
clamp_tester.perform_tests

# Regression: `option = default? ? "--json" : "--text"` inside the top-level
# `execute` method is an ordinary local-variable assignment, not a call into
# Clamp's `option "--flag", ...` DSL. CLAMP_OPTION_LONG must not treat the
# bare word "option" followed eventually by a quoted "--flag"-looking string
# as a DSL declaration, or it would attribute a phantom "json"/"text" flag
# to the root command.
it "does not attribute a bogus flag from a stray 'option' local variable (Clamp FP regression)" do
  root = clamp_tester.app.endpoints.find { |e| e.url == "cli://clamp_app" }
  root.should_not be_nil
  if root
    param_names = root.params.map(&.name)
    param_names.should_not contain("json")
    param_names.should_not contain("text")
  end
end

# --- dry-cli (Dry::CLI::Command subclass = subcommand + ENV) --------------
dry_cli_endpoints = [
  build.call("cli://dry_cli_app", [
    Param.new("DRY_CLI_TOKEN", "", "env"),
  ]),
  build.call("cli://dry_cli_app/build", [
    Param.new("force", "", "flag"),
    Param.new("target", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/ruby/cli_dry_cli/", {
  :techs     => 1,
  :endpoints => dry_cli_endpoints.size,
}, dry_cli_endpoints).perform_tests
