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

# --- clap nested subcommands + multi-line #[arg] + line-above #[command(name)]
clap_nested_endpoints = [
  build.call("cli://zoo/pen/open", [] of Param),
  build.call("cli://zoo/pen/close", [
    Param.new("amount", "", "flag"),
    Param.new("endpoint", "", "flag"),
    Param.new("speed", "", "flag"),
    Param.new("target", "", "flag"),
  ]),
  build.call("cli://zoo/__internal", [] of Param),
  # `Loop(CycleA)` -> `B(CycleB)` -> `Leaf`; the cycle back through
  # `CycleB::A` adds no second path.
  build.call("cli://zoo/loop/b/leaf", [] of Param),
]

FunctionalTester.new("fixtures/rust/cli_clap_nested/", {
  :techs     => 1,
  :endpoints => clap_nested_endpoints.size,
}, clap_nested_endpoints).perform_tests

# --- clap: variant wrapping an Args struct with a nested subcommand -------
# `Users(UsersArgs)` with `#[command(subcommand)] method: UsersMethod` inside
# the struct used to flatten `users get` onto `cli://tool/get`. The Parser
# struct's `#[command(name = "tool")]` used to rename `Orders`, the first
# variant after it, to `tool`. `users` keeps its own row (it wraps an Args
# struct); `orders` nests its enum directly and is only a path segment.
clap_args_nested_endpoints = [
  build.call("cli://tool/users", [] of Param),
  build.call("cli://tool/users/get", [Param.new("user-id", "", "flag")]),
  build.call("cli://tool/users/delete", [] of Param),
  build.call("cli://tool/orders/get", [Param.new("order-id", "", "flag")]),
  build.call("cli://tool/orders/cancel", [] of Param),
]

FunctionalTester.new("fixtures/rust/cli_clap_args_nested/", {
  :techs     => 1,
  :endpoints => clap_args_nested_endpoints.size,
}, clap_args_nested_endpoints).perform_tests

# --- clap: shared subcommand enum, Option subcommand, inline nesting -------
# `Crud` sits under both `users` and `orders`; `jobs` (an `Option<_>`
# subcommand) still runs alone; `keys { #[command(subcommand)] action }`
# nests `keys verify` instead of merging it into top-level `verify`. An Args
# struct's flags belong to the command that wraps it.
clap_shared_endpoints = [
  build.call("cli://sharedtool", [Param.new("verbose", "", "flag")]),
  build.call("cli://sharedtool/users", [Param.new("tenant", "", "flag")]),
  build.call("cli://sharedtool/users/get", [Param.new("id", "", "flag")]),
  build.call("cli://sharedtool/users/delete", [] of Param),
  build.call("cli://sharedtool/orders", [] of Param),
  build.call("cli://sharedtool/orders/get", [Param.new("id", "", "flag")]),
  build.call("cli://sharedtool/orders/delete", [] of Param),
  build.call("cli://sharedtool/jobs", [Param.new("all", "", "flag")]),
  build.call("cli://sharedtool/jobs/run", [] of Param),
  build.call("cli://sharedtool/keys", [Param.new("store", "", "flag")]),
  build.call("cli://sharedtool/keys/verify", [Param.new("keys-file", "", "flag")]),
  build.call("cli://sharedtool/verify", [Param.new("secret", "", "flag")]),
]

clap_shared_tester = FunctionalTester.new("fixtures/rust/cli_clap_shared/", {
  :techs     => 1,
  :endpoints => clap_shared_endpoints.size,
}, clap_shared_endpoints)
clap_shared_tester.perform_tests

# --- clap: per-module `Args` payloads next to a Parser named `Args` --------
clap_modules_endpoints = [
  build.call("cli://modtool/run", [Param.new("fast", "", "flag")]),
  build.call("cli://modtool/build", [Param.new("release", "", "flag")]),
  build.call("cli://modtool/status", [Param.new("json", "", "flag")]),
]

FunctionalTester.new("fixtures/rust/cli_clap_modules/", {
  :techs     => 1,
  :endpoints => clap_modules_endpoints.size,
}, clap_modules_endpoints).perform_tests

# --- clap: a cycle back to the top-level enum ------------------------------
# `As(AsArgs)` holds `Commands` again, so every enum is nested by some
# variant; the Parser's subcommand field still anchors the tree.
clap_cycle_endpoints = [
  build.call("cli://cycletool/users/get", [Param.new("user-id", "", "flag")]),
  build.call("cli://cycletool/admin/purge", [Param.new("all", "", "flag")]),
  build.call("cli://cycletool/admin/as", [Param.new("user", "", "flag")]),
]

FunctionalTester.new("fixtures/rust/cli_clap_cycle/", {
  :techs     => 1,
  :endpoints => clap_cycle_endpoints.size,
}, clap_cycle_endpoints).perform_tests

describe "rust CLI clap command tree", tags: "functional" do
  it "keeps an inline-nested subcommand's flags off the same-named top-level command" do
    verify = clap_shared_tester.endpoints.find! { |ep| ep.url == "cli://sharedtool/verify" }
    verify.params.map(&.name).should eq(["secret"])
    root = clap_shared_tester.endpoints.find! { |ep| ep.url == "cli://sharedtool" }
    root.params.map(&.name).should eq(["verbose"])
  end
end

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
