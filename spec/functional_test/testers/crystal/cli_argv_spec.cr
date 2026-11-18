require "../../func_spec.cr"

# Stdlib programs that read ARGV without OptionParser or indexing:
# `ARGV.first?`, `ARGV == [...]`, and `case ARGV.shift?` / `case ARGV[0]?`
# subcommand dispatch, including arms that name no subcommand.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://demo-dbtool", [
    Param.new("arg0", "", "argument"),
    Param.new("DEMO_DB_URL", "", "env"),
  ]),
  build.call("cli://worker", [
    Param.new("dry-run", "", "flag"),
    Param.new("DEMO_INTERVAL", "", "env"),
  ]),
  build.call("cli://ops", [
    Param.new("DEMO_DB_URL", "", "env"),
    Param.new("help", "", "flag"),
    Param.new("h", "", "flag"),
  ]),
  build.call("cli://ops/item-add", [
    Param.new("arg0", "", "argument"),
    Param.new("arg1", "", "argument"),
  ]),
  build.call("cli://ops/item-remove", [
    Param.new("arg0", "", "argument"),
  ]),
  build.call("cli://ops/item-list", [
    Param.new("limit", "", "flag"),
  ]),
  build.call("cli://tasks", [
    Param.new("DEMO_TOKEN", "", "env"),
  ]),
  build.call("cli://tasks/sync", [] of Param),
  build.call("cli://tasks/purge", [
    Param.new("force", "", "flag"),
  ]),
  build.call("cli://tasks/report", [
    Param.new("arg0", "", "argument"),
  ]),
  build.call("cli://pager", [
    Param.new("v", "", "flag"),
    Param.new("version", "", "flag"),
    Param.new("arg0", "", "argument"),
  ]),
  build.call("cli://counter", [
    Param.new("arg0", "", "argument"),
  ]),
  build.call("cli://notes/add", [
    Param.new("arg0", "", "argument"),
  ]),
]
FunctionalTester.new("fixtures/crystal/cli_argv/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests
