require "../../func_spec.cr"

# JSON-RPC selects the operation via the request body, not the path, so every
# method shares one HTTP endpoint. URLs use a `/rpc#<method>` fragment — the
# same trick the GraphQL SDL analyzer uses — so the optimizer's (method, url)
# dedupe keeps each RPC method distinct instead of merging them into one.
#
# `blockNumber` on eth_getBalance comes from a `$ref` into
# components.contentDescriptors, so this also covers ref reuse.
FunctionalTester.new("fixtures/specification/openrpc/common/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/rpc#eth_getBalance", "POST", [
    Param.new("address", "", "json"),
    Param.new("blockNumber", "", "json"),
    Param.new("jsonrpc_eth_getBalance", "", "json"),
  ]),
  Endpoint.new("/rpc#eth_blockNumber", "POST", [
    Param.new("jsonrpc_eth_blockNumber", "", "json"),
  ]),
  Endpoint.new("/rpc#session_login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("jsonrpc_session_login", "", "json"),
  ]),
]).perform_tests

# A server `url` of `{endpoint}` is the whole base URL, not a path segment:
# a `default` is substituted the way OAS3 does it, and with no default the
# server is unusable, so the method falls back to the root.
FunctionalTester.new("fixtures/specification/openrpc/server_variables/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/v1/rpc#node_status", "POST", [
    Param.new("jsonrpc_node_status", "", "json"),
  ]),
  Endpoint.new("/#node_peers", "POST", [
    Param.new("jsonrpc_node_peers", "", "json"),
  ]),
]).perform_tests
