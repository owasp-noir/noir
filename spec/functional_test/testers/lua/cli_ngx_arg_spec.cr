require "../../func_spec.cr"

# Regression: OpenResty's `ngx.arg[1]` / `ngx.arg[2]` (body-filter chunk and
# eof), a `ctx.arg[1]` field read, and a bare `arg[1]` in a file that aliases
# `local arg = ngx.arg` are not argv. Only tool.lua's real `arg[N]` reads
# produce a cli:// endpoint; the two filters (one with an os.getenv) produce none.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

ngx_arg_endpoints = [
  build.call("cli://tool", [
    Param.new("arg1", "", "argument"),
    Param.new("arg2", "", "argument"),
  ]),
]
FunctionalTester.new("fixtures/lua/cli_ngx_arg/", {:techs => 1, :endpoints => ngx_arg_endpoints.size}, ngx_arg_endpoints).perform_tests
