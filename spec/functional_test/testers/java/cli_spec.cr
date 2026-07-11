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

# jopt-simple (root flags only, no subcommands): `.accepts("flag")` and
# `.acceptsAll(Arrays.asList("h", "help"), ...)` (first alias) on the tracked
# `OptionParser` variable, plus gated System.getenv.
jopt_simple_endpoints = [
  build.call("cli://App", [
    Param.new("verbose", "", "flag"),
    Param.new("h", "", "flag"),
    Param.new("APP_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/java/cli_jopt_simple/", {
  :techs     => 1,
  :endpoints => jopt_simple_endpoints.size,
}, jopt_simple_endpoints).perform_tests

# Regression (attribution false positive): a genuine jopt-simple parser bound
# to `parser` sits alongside an unrelated `FormatMatcher.accepts(String)`
# method called as `matcher.accepts("csv")`. Only the real `.accepts("topic")`
# on the tracked `parser` variable may surface as a flag — "csv" from the
# untracked `matcher` receiver must NOT appear.
jopt_simple_fp_endpoints = [
  build.call("cli://App", [
    Param.new("topic", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/java/cli_jopt_simple_fp/", {
  :techs     => 1,
  :endpoints => jopt_simple_fp_endpoints.size,
}, jopt_simple_fp_endpoints).perform_tests

# Regression (detector false positive): a class literally named `OptionParser`
# with no `joptsimple.` import anywhere must NOT be tagged java_cli — the
# generic class name alone isn't a reliable jopt-simple signal.
FunctionalTester.new("fixtures/java/cli_optionparser_generic_fp/", {
  :techs     => 0,
  :endpoints => 0,
}, [] of Endpoint).perform_tests
