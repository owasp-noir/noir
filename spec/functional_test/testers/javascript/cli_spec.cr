require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so
# build via a Proc that mutates a local and returns it.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- commander (program/command + option/argument + process.env) -----------
commander_endpoints = [
  build.call("cli://commanderdemo", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://commanderdemo/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_commander/", {
  :techs     => 1,
  :endpoints => commander_endpoints.size,
}, commander_endpoints).perform_tests

# --- yargs (option + command + positional) ---------------------------------
yargs_endpoints = [
  build.call("cli://yargsdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://yargsdemo/serve", [
    Param.new("port", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_yargs/", {
  :techs     => 1,
  :endpoints => yargs_endpoints.size,
}, yargs_endpoints).perform_tests

# --- arg (object-schema flags, quoted-string aliases skipped) --------------
arg_endpoints = [
  build.call("cli://argdemo", [
    Param.new("name", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_arg/", {
  :techs     => 1,
  :endpoints => arg_endpoints.size,
}, arg_endpoints).perform_tests

# --- command-line-args (option-definitions array + defaultOption) ----------
command_line_args_endpoints = [
  build.call("cli://claddemo", [
    Param.new("verbose", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("file", "", "argument"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_command_line_args/", {
  :techs     => 1,
  :endpoints => command_line_args_endpoints.size,
}, command_line_args_endpoints).perform_tests

# --- getopts (alias/default/boolean/string option-config) ------------------
getopts_endpoints = [
  build.call("cli://getoptsdemo", [
    Param.new("help", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("name", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_getopts/", {
  :techs     => 1,
  :endpoints => getopts_endpoints.size,
}, getopts_endpoints).perform_tests

# --- citty (defineCommand args + nested subCommands) ------------------------
citty_endpoints = [
  build.call("cli://cittydemo", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://cittydemo/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_citty/", {
  :techs     => 1,
  :endpoints => citty_endpoints.size,
}, citty_endpoints).perform_tests

# --- command-line-args false-positive regression ----------------------------
# A real `commandLineArgs(optionDefinitions)` call sits alongside an unrelated
# array of `{ name, type }` content-field objects; the unrelated array must
# never leak "email"/"age" onto the endpoint as phantom flags (CLA_OPTION_RE
# used to be an unscoped whole-file scan).
cla_fp_endpoints = [
  build.call("cli://cladfpdemo", [
    Param.new("verbose", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_command_line_args_fp/", {
  :techs     => 1,
  :endpoints => cla_fp_endpoints.size,
}, cla_fp_endpoints).perform_tests

describe "command-line-args scoping keeps unrelated fields out" do
  tester = FunctionalTester.new("fixtures/javascript/cli_command_line_args_fp/", {
    :techs => 1,
  }, [] of Endpoint)

  locator = CodeLocator.instance
  locator.clear_all
  tester.app.detect
  tester.app.analyze

  endpoint = tester.app.endpoints.find { |ep| ep.url == "cli://cladfpdemo" }

  it "does not leak the unrelated 'email'/'age' field-schema keys as flags" do
    endpoint.should_not be_nil
    if endpoint
      bogus = endpoint.params.select { |p| {"email", "age"}.includes?(p.name) }
      bogus.size.should eq(0)
    end
  end
end

# --- command-line-args multi-line (Prettier-style) option entries ----------
# Each option object is spread across multiple lines instead of a single
# line; both flags must still be extracted (CLA_OPTION_RE used to require
# `name:` and `type:` on the very same physical line).
cla_multiline_endpoints = [
  build.call("cli://clamultilinedemo", [
    Param.new("verbose", "", "flag"),
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_command_line_args_multiline/", {
  :techs     => 1,
  :endpoints => cla_multiline_endpoints.size,
}, cla_multiline_endpoints).perform_tests

# --- getopts bare-substring false-positive regression -----------------------
# A real commander-based CLI file sits alongside an unrelated module whose
# only connection to "getopts" is the bare word inside a comment (no
# `require('getopts')`/`getopts(...)` call at all). That file must not be
# treated as CLI evidence, so its `process.env.API_TOKEN` read must not be
# attached to the shared cli:// endpoint as a phantom env param.
getopts_fp_endpoints = [
  build.call("cli://getoptsfpdemo", [
    Param.new("verbose", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_getopts_fp/", {
  :techs     => 1,
  :endpoints => getopts_fp_endpoints.size,
}, getopts_fp_endpoints).perform_tests

describe "bare 'getopts' substring does not grant CLI evidence" do
  tester = FunctionalTester.new("fixtures/javascript/cli_getopts_fp/", {
    :techs => 1,
  }, [] of Endpoint)

  locator = CodeLocator.instance
  locator.clear_all
  tester.app.detect
  tester.app.analyze

  endpoint = tester.app.endpoints.find { |ep| ep.url == "cli://getoptsfpdemo" }

  it "does not attach API_TOKEN from the getopts-comment-only file" do
    endpoint.should_not be_nil
    if endpoint
      bogus = endpoint.params.select { |p| p.name == "API_TOKEN" }
      bogus.size.should eq(0)
    end
  end
end

# --- citty variable-referenced subcommand attribution -----------------------
# `serve: serveCommand` (a top-level `const serveCommand = defineCommand({...})`
# referenced by identifier) must resolve to its own `cli://<binary>/serve`
# endpoint instead of falling back to root (CITTY_SUBCOMMAND_RE used to only
# recognize the inline `key: defineCommand({ ... })` nesting pattern).
citty_var_endpoints = [
  build.call("cli://cittyvardemo/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_citty_var_subcommand/", {
  :techs     => 1,
  :endpoints => citty_var_endpoints.size,
}, citty_var_endpoints).perform_tests
