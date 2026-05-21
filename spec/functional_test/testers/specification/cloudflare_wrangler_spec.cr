require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api.example.com/*", "ANY"),
  Endpoint.new("/example.com/api/*", "ANY"),
]

FunctionalTester.new("fixtures/specification/cloudflare_wrangler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
