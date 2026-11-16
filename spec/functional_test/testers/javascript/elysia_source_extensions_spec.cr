require "../../func_spec.cr"

expected_endpoints = %w[js mjs cjs jsx ts mts cts tsx].map { |extension| Endpoint.new("/#{extension}", "GET") }

FunctionalTester.new("fixtures/javascript/elysia_source_extensions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
