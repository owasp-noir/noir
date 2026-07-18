require "../../func_spec.cr"

expected_endpoints = [
  # API Gateway v2 (HTTP API) — self-contained route_key
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/{id}", "GET"),
  # API Gateway v1 (REST) — resource graph resolved across files in the module
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET"),
  # Terraform JSON (.tf.json), routed through the real file-walk .json filter
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/specification/terraform/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
