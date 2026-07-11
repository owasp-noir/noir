require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [Param.new("file", "", "argument")]),
]
FunctionalTester.new("fixtures/scala/cli_scopt/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

# Scallop (org.rogach.scallop): `val serve = new Subcommand("serve") { ... }`
# idiom. Regression for a reviewer finding: Scallop's bare `opt[T]("name")`
# is textually identical to scopt's `opt[T]("name")`, so an ungated scopt
# extractor would also fire on this file and attach the subcommand-only
# `port`/`file` params to the root `cli://tool` endpoint even though
# Scallop's own subcommand scoping correctly binds them to `cli://tool/serve`
# only. Reproduced against a deliberately ungated build: root came back with
# params [verbose, port, API_TOKEN] instead of [verbose, API_TOKEN].
scallop_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("file", "", "argument"),
  ]),
]
scallop_tester = FunctionalTester.new("fixtures/scala/cli_scallop/", {:techs => 1, :endpoints => scallop_endpoints.size}, scallop_endpoints)
scallop_tester.perform_tests

describe "scala scallop: subcommand-only opts must not leak onto the root endpoint" do
  it "cli://tool does not contain the subcommand-scoped 'port'/'file' params" do
    root = scallop_tester.app.endpoints.find { |e| e.url == "cli://tool" }
    root.should_not be_nil
    names = root.not_nil!.params.map(&.name)
    names.should_not contain("port")
    names.should_not contain("file")
  end
end

# Scallop's idiomatic `object serve extends Subcommand("serve") { ... }` form
# (shown in Scallop's own docs) plus the macro-based inferred-name overload
# `opt[T]()` (name taken from the enclosing `val`). Regression for a reviewer
# finding: a scope-detection regex that only recognized the `val x =
# Subcommand(...)` idiom silently merged this subcommand's flags into the
# root and never created a `cli://tool/serve` endpoint at all. Reproduced
# against a deliberately narrowed SCALLOP_SUBCMD regex: single root endpoint
# with params [verbose, port, file, API_TOKEN], no /serve endpoint.
scallop_object_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("file", "", "argument"),
  ]),
]
scallop_object_tester = FunctionalTester.new("fixtures/scala/cli_scallop_object_fp/", {:techs => 1, :endpoints => scallop_object_endpoints.size}, scallop_object_endpoints)
scallop_object_tester.perform_tests

describe "scala scallop: 'object x extends Subcommand(...)' idiom creates a scoped subcommand endpoint" do
  it "cli://tool/serve exists and cli://tool does not contain its params" do
    endpoints_found = scallop_object_tester.app.endpoints
    serve = endpoints_found.find { |e| e.url == "cli://tool/serve" }
    serve.should_not be_nil

    root = endpoints_found.find { |e| e.url == "cli://tool" }
    root.should_not be_nil
    names = root.not_nil!.params.map(&.name)
    names.should_not contain("port")
    names.should_not contain("file")
  end
end

# com.twitter.app: `flag[T]("name", ...)` always takes an explicit name (no
# reflection/macro-based no-arg overload the way Scallop infers names from a
# `val`), so only the explicitly-named form is exercised here.
twitter_endpoints = [
  build.call("cli://tool", [
    Param.new("retries", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/scala/cli_twitter/", {:techs => 1, :endpoints => twitter_endpoints.size}, twitter_endpoints).perform_tests
