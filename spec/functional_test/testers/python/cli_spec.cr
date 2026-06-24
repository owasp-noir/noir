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
