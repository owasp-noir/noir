require "../../func_spec.cr"

# Real Grape apps share a custom base class and aggregate sub-APIs with
# `mount`, declaring the global `prefix` + path `version` only on the root.
# Route files inherit from the base and never name `Grape::API`. This
# fixture exercises the full chain: custom-base recognition, `/api/v1`
# mount-prefix propagation, `resource`/`route_param` with trailing kwargs,
# and a nested non-Grape helper class that must not steal the aggregator's
# declarations.
expected_endpoints = [
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/widgets", "POST"),
]

FunctionalTester.new("fixtures/ruby/grape_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
