require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("help", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("file", "", "argument"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_clap/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

args_endpoints = [
  build.call("cli://tool", [
    Param.new("help", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("output", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_args/", {:techs => 1, :endpoints => args_endpoints.size}, args_endpoints).perform_tests

yazap_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("input", "", "argument"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://tool/build", [
    Param.new("release", "", "flag"),
    Param.new("output", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_yazap/", {:techs => 1, :endpoints => yazap_endpoints.size}, yazap_endpoints).perform_tests

# Regression: an unrelated `.parse(NetConfig, ...)` call on a receiver that
# is NOT the zig-args alias (and an unrelated struct) must not hijack
# extraction or steal the "first match" slot from the real
# argsParser.parseForCurrentProcess(Options, ...) call. `host`/`port` must
# never appear, and the real `help`/`verbose` fields must still be found.
args_fp_endpoints = [
  build.call("cli://tool", [
    Param.new("help", "", "flag"),
    Param.new("verbose", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_args_fp/", {:techs => 1, :endpoints => args_fp_endpoints.size}, args_fp_endpoints).perform_tests

# Regression: a generic yazap receiver variable (`cmd`) reused across two
# subcommands. The flag added to `cmd` BEFORE it is reassigned must resolve
# to the command bound to it AT THAT LINE ("build"), not to whichever
# command is assigned LAST in the file ("test") -- `build` must keep
# `release` and must NOT also pick up `verbose`.
yazap_fp_endpoints = [
  build.call("cli://tool/build", [
    Param.new("release", "", "flag"),
  ]),
  build.call("cli://tool/test", [
    Param.new("verbose", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/zig/cli_yazap_fp/", {:techs => 1, :endpoints => yazap_fp_endpoints.size}, yazap_fp_endpoints).perform_tests

# Regression: a bare `@import("args")` used for something unrelated to
# process argv parsing (no parseForCurrentProcess/parse call bound to the
# alias anywhere in the file) must not seed a zero-evidence `cli://<binary>`
# root endpoint.
FunctionalTester.new("fixtures/zig/cli_args_bare_import_fp/", {:techs => 1, :endpoints => 0}, [] of Endpoint).perform_tests
