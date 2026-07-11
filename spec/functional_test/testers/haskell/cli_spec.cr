require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [Param.new("host", "", "flag")]),
]
FunctionalTester.new("fixtures/haskell/cli_optparse/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

turtle_endpoints = [
  build.call("cli://tool", [
    Param.new("name", "", "flag"),
    Param.new("age", "", "flag"),
    Param.new("config", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("target", "", "argument"),
    Param.new("GREETING_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/haskell/cli_turtle/", {:techs => 1, :endpoints => turtle_endpoints.size}, turtle_endpoints).perform_tests

# Regression coverage for the Tier-3 hardening review: a genuine Turtle CLI
# file that ALSO contains adjacent code which used to trip the old
# TURTLE_SWITCH / TURTLE_ARG_FN regexes (a locally-defined `switch` string
# dispatcher, a stale `-- arg ...` comment, and a call site literally
# `logMessage arg level "urgent"`), plus real Turtle.Options idioms the old
# regexes missed (argInt, and `arg` with a parenthesized/dot-composed
# reader). Only the genuine CLI params must appear -- "urgent", "deprecated",
# "on", and "staging" must never show up as params.
turtle_fp_endpoints = [
  build.call("cli://tool", [
    Param.new("name", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("target", "", "argument"),
    Param.new("retries", "", "argument"),
    Param.new("count", "", "argument"),
    Param.new("GREETING_TOKEN", "", "env"),
  ]),
]
turtle_fp_tester = FunctionalTester.new("fixtures/haskell/cli_turtle_fp/", {:techs => 1, :endpoints => turtle_fp_endpoints.size}, turtle_fp_endpoints)
turtle_fp_tester.perform_tests

it "does not leak bogus params from adjacent non-Turtle code into the Turtle CLI endpoint" do
  endpoint = turtle_fp_tester.app.endpoints.find! { |e| e.method == "CLI" && e.url == "cli://tool" }
  endpoint.params.map(&.name).sort!.should eq ["GREETING_TOKEN", "count", "name", "retries", "target", "verbose"]
end
