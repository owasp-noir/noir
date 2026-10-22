require "../../func_spec.cr"

# Quart shares the Blueprint-subclass url_prefix handling with Flask: a route
# on `class ApiBlueprint(Blueprint)` is served under the instance's prefix,
# never bare.
expected_endpoints = [
  Endpoint.new("/items/list", "GET"),
]

FunctionalTester.new("fixtures/python/quart_blueprint_subclass/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
