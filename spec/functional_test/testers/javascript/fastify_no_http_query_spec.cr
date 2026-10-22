require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/direct-query", "QUERY"),
]

FunctionalTester.new("fixtures/javascript/fastify_no_http_query/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
