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
  ]),
]
FunctionalTester.new("fixtures/groovy/cli_clibuilder/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

# JCommander: @Parameter fields, addObject() root binding, and both
# addCommand subcommand registration styles -- inline `addCommand("name",
# new Class())` and declare-then-register `addCommand("name", var)` where
# `var` was assigned via `def var = new Class()` earlier in the file.
# Regression for: sub-command flags silently collapsing into the root
# endpoint when only the declare-then-register form is used.
jcommander_endpoints = [
  build.call("cli://tool", [
    Param.new("file", "", "flag"),
    Param.new("JC_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/add", [
    Param.new("message", "", "flag"),
  ]),
  build.call("cli://tool/remove", [
    Param.new("recursive", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/groovy/cli_jcommander/", {
  :techs     => 1,
  :endpoints => jcommander_endpoints.size,
}, jcommander_endpoints).perform_tests

# Commons CLI: Option.builder("short").longOpt(...), the long-only
# Option.builder() form (no short name at all), and two Option.builder(...)
# chains on the same source line separated by `;`. Regression for: the
# long-only form being silently dropped, and only the first of several
# same-line options being captured.
commons_cli_endpoints = [
  build.call("cli://tool", [
    Param.new("file", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("quiet", "", "flag"),
    Param.new("CLI_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/groovy/cli_commons_cli/", {
  :techs     => 1,
  :endpoints => commons_cli_endpoints.size,
}, commons_cli_endpoints).perform_tests
