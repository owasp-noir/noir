require "../../func_spec.cr"

# `a.or(b)` written inline in one binding or fn tail is two routes. Each
# alternative keeps its own path and verb, including nested `.or` chains
# and alternatives followed by a trailing `.recover(..)`. Verbs, bodies and
# segments chained after the `.or` (path aliases) apply to every alternative.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/bye", "POST"),
  Endpoint.new("/a", "PUT"),
  Endpoint.new("/b", "DELETE"),
  Endpoint.new("/c", "GET"),
  Endpoint.new("/x", "POST", [Param.new("Item", "", "json")]),
  Endpoint.new("/y", "POST", [Param.new("Item", "", "json")]),
  Endpoint.new("/v1/items/:param", "DELETE", [Param.new("param", "", "path")]),
  Endpoint.new("/v2/items/:param", "DELETE", [Param.new("param", "", "path")]),
]

FunctionalTester.new("fixtures/rust/warp_or/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
