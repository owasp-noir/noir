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

# --- kong (struct-tag CLI: cmd/arg/env/default field tags) -----------------
kong_endpoints = [
  build.call("cli://kongdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://kongdemo/serve", [
    Param.new("host", "", "argument"),
    Param.new("port", "", "flag"),
    Param.new("token", "", "flag"),
    Param.new("KONG_API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_kong/", {
  :techs     => 1,
  :endpoints => kong_endpoints.size,
}, kong_endpoints).perform_tests

# --- kingpin (fluent Flag/Arg/Command builder, receiver-scoped) ------------
kingpin_endpoints = [
  build.call("cli://kingpindemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://kingpindemo/deploy", [
    Param.new("target", "", "argument"),
    Param.new("token", "", "flag"),
    Param.new("KINGPIN_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_kingpin/", {
  :techs     => 1,
  :endpoints => kingpin_endpoints.size,
}, kingpin_endpoints).perform_tests

# --- mitchellh/cli (Commands map of factories, Run()-scoped flags) ---------
mitchellh_endpoints = [
  build.call("cli://mitchellhdemo/deploy", [
    Param.new("target", "", "flag"),
    Param.new("MITCHELLH_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_mitchellh/", {
  :techs     => 1,
  :endpoints => mitchellh_endpoints.size,
}, mitchellh_endpoints).perform_tests

# --- kong: unrelated struct with common tag keys must not leak onto root ---
# ClientConfig is parsed by envconfig (not kong) but shares kong's tag keys
# (env/default). Its `timeout`/`HTTP_TIMEOUT` must never appear anywhere —
# regression for the `type_urls[current_type]? || root_url` fallback that
# used to merge any unrecognized struct onto the CLI root.
kong_fp_endpoints = [
  build.call("cli://kongfpdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://kongfpdemo/serve", [
    Param.new("host", "", "argument"),
    Param.new("port", "", "flag"),
    Param.new("token", "", "flag"),
    Param.new("KONG_API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_kong_fp/", {
  :techs     => 1,
  :endpoints => kong_fp_endpoints.size,
}, kong_fp_endpoints).perform_tests

# --- kong: pointer-typed cmd:"" subcommand field ----------------------------
# `Serve *ServeCmd `cmd:""`` (valid kong syntax for optional subcommands)
# must resolve its own flags/args onto /serve, not leak them onto root.
kong_ptr_endpoints = [
  build.call("cli://kongptrdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://kongptrdemo/serve", [
    Param.new("host", "", "argument"),
    Param.new("port", "", "flag"),
    Param.new("token", "", "flag"),
    Param.new("KONG_API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_kong_ptr/", {
  :techs     => 1,
  :endpoints => kong_ptr_endpoints.size,
}, kong_ptr_endpoints).perform_tests

# --- mitchellh/cli: intermediate-variable return + unrelated function ------
# DeployCommand is returned via `cmd := &DeployCommand{}; return cmd, nil`
# (idiomatic when the command needs field initialization) instead of the
# single-expression `return &DeployCommand{}, nil`. A later, unrelated
# `adminHelper` function returning `&AdminCommand{}, nil` must never be
# attributed to /deploy — regression for the sticky `pending_key` cursor
# that used to leak past the closing of the map literal.
mitchellh_fp_endpoints = [
  build.call("cli://mitchellhfpdemo/deploy", [
    Param.new("target", "", "flag"),
    Param.new("MITCHELLH_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/go/cli_mitchellh_fp/", {
  :techs     => 1,
  :endpoints => mitchellh_fp_endpoints.size,
}, mitchellh_fp_endpoints).perform_tests

# FunctionalTester only asserts that EXPECTED params are present on an
# endpoint (a subset match) and that the total endpoint COUNT matches — it
# never asserts that an endpoint's param list contains NOTHING else. That
# means a leaked param merged onto an endpoint that already has legitimate
# params (e.g. root's pre-existing "verbose") would silently pass the
# blocks above even on the old buggy code. Assert the exact negative
# directly so these regressions truly fail on the old fallback/sticky-cursor
# behavior and pass only once the leak is gone.
describe "go CLI attribution false-positive guards" do
  it "does not leak an unrelated envconfig-tagged struct's fields onto the kong root command" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/cli_kong_fp/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    root = app.endpoints.find! { |ep| ep.url == "cli://kongfpdemo" }
    root.params.map(&.name).should_not contain("timeout")
    root.params.map(&.name).should_not contain("HTTP_TIMEOUT")
    root.params.size.should eq(1)

    serve = app.endpoints.find! { |ep| ep.url == "cli://kongfpdemo/serve" }
    serve.params.map(&.name).should_not contain("timeout")
    serve.params.map(&.name).should_not contain("HTTP_TIMEOUT")
  end

  it "does not leak an unrelated function's return type onto a mitchellh/cli command via a stale pending_key cursor" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/cli_mitchellh_fp/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.map(&.url).should_not contain("cli://mitchellhfpdemo/admin")

    deploy = app.endpoints.find! { |ep| ep.url == "cli://mitchellhfpdemo/deploy" }
    deploy.params.map(&.name).should_not contain("ADMIN_TOKEN")
    deploy.params.size.should eq(2)
  end
end
