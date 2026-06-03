require "../../func_spec.cr"

# Connect-RPC repo that ships ONLY generated code (no committed
# `.proto`). The `*Procedure` constants in `*.connect.go` are the only
# route source; the analyzer's connect.go fallback surfaces them (it
# previously returned zero endpoints when no proto was present).
# Streaming shape is recovered from the `connect.NewXxxHandler(...)`
# constructors. No params — there's no proto message to read fields from.
expected_endpoints = [
  Endpoint.new("/connectrpc.eliza.v1.ElizaService/Say", "POST"),
  Endpoint.new("/connectrpc.eliza.v1.ElizaService/Converse", "POST"),
  Endpoint.new("/connectrpc.eliza.v1.ElizaService/Introduce", "POST"),
]

# Only `go_connect_rpc` is detected — without a `.proto` the gRPC spec
# detector doesn't fire.
FunctionalTester.new("fixtures/go/connect_rpc_protoless/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
