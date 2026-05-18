require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/english/hello", "GET"),
  Endpoint.new("/italian/hello", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_inline_register_prefix/", {
  :techs => 1,
}, expected_endpoints).perform_tests
