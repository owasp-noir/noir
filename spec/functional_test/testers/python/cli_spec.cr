require "../../func_spec.cr"

# CLI endpoints carry the synthetic "CLI" method; the surface lives in
# protocol "cli" plus flag/argument/env params. Endpoint is a struct, so
# build via a Proc that mutates a local and returns it (a `.tap` block would
# mutate a copy). FunctionalTester asserts protocol (≠ "http") and params.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- argparse (parser + subparsers + os.environ) ---------------------------
argparse_endpoints = [
  build.call("cli://pytool", [
    Param.new("verbose", "", "flag"),
    Param.new("output", "", "flag"),
    Param.new("source", "", "argument"),
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://pytool/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/python/cli/", {
  :techs     => 1,
  :endpoints => argparse_endpoints.size,
}, argparse_endpoints).perform_tests

# --- click (group + command + options/arguments + envvar) ------------------
click_endpoints = [
  build.call("cli://clicktool", [
    Param.new("config", "", "flag"),
    Param.new("APP_CONFIG", "", "env"),
  ]),
  build.call("cli://clicktool/serve", [
    Param.new("port", "", "flag"),
    Param.new("name", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/python/cli_click/", {
  :techs     => 1,
  :endpoints => click_endpoints.size,
}, click_endpoints).perform_tests

# --- typer (command + typed params + envvar + os.getenv) -------------------
typer_endpoints = [
  build.call("cli://typertool/serve", [
    Param.new("port", "", "flag"),
    Param.new("name", "", "argument"),
    Param.new("TYPER_PORT", "", "env"),
  ]),
  build.call("cli://typertool", [
    Param.new("TYPER_TOKEN", "", "env"),
  ]),
]

FunctionalTester.new("fixtures/python/cli_typer/", {
  :techs     => 1,
  :endpoints => typer_endpoints.size,
}, typer_endpoints).perform_tests

# --- absl-py (Abseil flags: a single flat flag namespace) -------------------
absl_endpoints = [
  build.call("cli://abslapp", [
    Param.new("name", "", "flag"),
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("mode", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/python/cli_absl/", {
  :techs     => 1,
  :endpoints => absl_endpoints.size,
}, absl_endpoints).perform_tests

# --- Cleo (Command subclass + self.argument/self.option readback) ----------
cleo_endpoints = [
  build.call("cli://cleotool", [
    Param.new("CLEO_TOKEN", "", "env"),
  ]),
  build.call("cli://cleotool/greet", [
    Param.new("name", "", "argument"),
    Param.new("yell", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/python/cli_cleo/", {
  :techs     => 1,
  :endpoints => cleo_endpoints.size,
}, cleo_endpoints).perform_tests

# --- Cleo attribution regression: a same-named local variable inside a
# method body (defined ABOVE the real `name = "..."` class attribute) must
# not hijack the resolved command URL. Only the class's direct-member
# `name = "greet"` counts; `setup`'s local `name = "temp-setup-value"` does
# not. -----------------------------------------------------------------------
cleo_attribution_fp_endpoints = [
  build.call("cli://greettool/greet", [
    Param.new("name", "", "argument"),
  ]),
]

FunctionalTester.new("fixtures/python/cli_cleo_attribution_fp/", {
  :techs     => 1,
  :endpoints => cleo_attribution_fp_endpoints.size,
}, cleo_attribution_fp_endpoints).perform_tests

# --- Cleo false-positive regression: a `class Foo(Command)` nested inside a
# factory function is never resolved by scan_cleo's column-0-anchored
# extraction, so cli_entrypoint? must not treat the file as a CLI surface on
# the strength of that class alone. Without the fix this used to emit a
# bogus `cli://factory` endpoint carrying an unrelated env var purely because
# the entrypoint gate and the extractor disagreed on what counts as a class
# declaration. -----------------------------------------------------------
FunctionalTester.new("fixtures/python/cli_cleo_nested_fp/", {
  :techs     => 1,
  :endpoints => 0,
}, [] of Endpoint).perform_tests
