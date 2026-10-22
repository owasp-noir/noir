require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# CLI11 (App + add_flag + add_subcommand + add_option, std::getenv,
# raw argv[N] positional)
endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
    Param.new("arg1", "", "argument"),
  ]),
  build.call("cli://tool/serve", [
    Param.new("port", "", "flag"),
    Param.new("config", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/cpp/cli_cli11/", {
  :techs     => 1,
  :endpoints => endpoints.size,
}, endpoints).perform_tests

# argparse false-positive regression: a helper function's own local
# ArgumentParser (declared textually before main's) must not be mistaken
# for the root, and its --log-level option must not leak into the real
# root's endpoint. Only the actual root (bound via .parse_args(argc, argv))
# surfaces, with exactly its own flags.
argparse_fp_endpoints = [
  build.call("cli://mytool", [
    Param.new("verbose", "", "flag"),
    Param.new("config", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/cpp/cli_argparse_fp/", {
  :techs     => 1,
  :endpoints => argparse_fp_endpoints.size,
}, argparse_fp_endpoints).perform_tests

# argparse subcommand binding, declare-then-register order: the subcommand
# parser is declared and linked via add_subparser *before* the root's own
# add_argument/parse_args lines, proving attribution doesn't depend on
# source order.
argparse_sub_endpoints = [
  build.call("cli://git", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://git/commit", [
    Param.new("message", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/cpp/cli_argparse_sub/", {
  :techs     => 1,
  :endpoints => argparse_sub_endpoints.size,
}, argparse_sub_endpoints).perform_tests

# Abseil Flags: ABSL_FLAG with a space before the paren must still be
# detected/extracted, and a template type with a top-level comma
# (std::map<std::string, int>) must not truncate the name field.
absl_fp_endpoints = [
  build.call("cli://server", [
    Param.new("port", "", "flag"),
    Param.new("weights", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/cpp/cli_absl_fp/", {
  :techs     => 1,
  :endpoints => absl_fp_endpoints.size,
}, absl_fp_endpoints).perform_tests
