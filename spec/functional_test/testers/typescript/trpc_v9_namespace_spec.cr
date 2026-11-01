require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/trpc/sub.a", "GET", [
    Param.new("input", "", "query"),
  ]),
  Endpoint.new("/api/trpc/m", "POST"),
]

FunctionalTester.new("fixtures/typescript/trpc_v9_namespace/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("ts_trpc"),
}).perform_tests
