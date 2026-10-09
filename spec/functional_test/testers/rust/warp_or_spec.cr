require "../../func_spec.cr"

# `a.or(b)` written inline in one binding or fn tail is two routes. Each
# alternative keeps its own path and verb, including nested `.or` chains
# and alternatives followed by a trailing `.recover(..)`.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/bye", "POST"),
  Endpoint.new("/a", "PUT"),
  Endpoint.new("/b", "DELETE"),
  Endpoint.new("/c", "GET"),
]

FunctionalTester.new("fixtures/rust/warp_or/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
