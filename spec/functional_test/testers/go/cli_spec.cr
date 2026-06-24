require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the real surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so a
# `.tap(&.protocol=)` block would mutate a copy — build via a Proc that
# mutates a local and returns it, which persists. FunctionalTester then
# asserts the protocol (since it differs from "http") and the params.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- stdlib flag + os.Args + os.Getenv -------------------------------------
builtin_endpoints = [
  build.call("cli://clitool", [
    Param.new("name", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
    Param.new("arg1", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/go/cli/", {
  :techs     => 1,
  :endpoints => builtin_endpoints.size,
}, builtin_endpoints).perform_tests

# --- cobra (command tree + persistent/local flags + viper env) -------------
cobra_endpoints = [
  build.call("cli://cobrademo", [
    Param.new("verbose", "", "flag"),
    Param.new("COBRA_API_KEY", "", "env"),
  ]),
  build.call("cli://cobrademo/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_cobra/", {
  :techs     => 1,
  :endpoints => cobra_endpoints.size,
}, cobra_endpoints).perform_tests

# --- cobra with a Use-less root command -----------------------------------
# A root command that omits `Use:` must keep its flags on the root and must
# not borrow the `serve` subcommand's Use token (regression for the
# struct-bounded Use scan).
cobra_root_endpoints = [
  build.call("cli://rootless", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://rootless/serve", [] of Param),
]

FunctionalTester.new("fixtures/go/cli_cobra_root/", {
  :techs     => 1,
  :endpoints => cobra_root_endpoints.size,
}, cobra_root_endpoints).perform_tests

# --- urfave/cli (app + command + flags + EnvVars) --------------------------
urfave_endpoints = [
  build.call("cli://urfavedemo", [
    Param.new("config", "", "flag"),
    Param.new("URFAVE_CONFIG", "", "env"),
  ]),
  build.call("cli://urfavedemo/deploy", [
    Param.new("target", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_urfave/", {
  :techs     => 1,
  :endpoints => urfave_endpoints.size,
}, urfave_endpoints).perform_tests
