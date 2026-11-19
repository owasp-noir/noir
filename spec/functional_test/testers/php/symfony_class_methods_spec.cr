require "../../func_spec.cr"

# A class-level `#[Route(methods: [...])]` adds its verbs to each method
# route's: `/inherit` is POST only, `/own` both POST and PUT.
expected_endpoints = [
  Endpoint.new("/v1/inherit", "POST"),
  Endpoint.new("/v1/own", "POST"),
  Endpoint.new("/v1/own", "PUT"),
]

FunctionalTester.new("fixtures/php/symfony_class_methods/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
