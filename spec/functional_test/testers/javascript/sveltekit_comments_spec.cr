require "../../func_spec.cr"

# Commented-out verb exports and form actions are not routes.
expected_endpoints = [
  Endpoint.new("/login", "GET"),
  Endpoint.new("/api/todos/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/sveltekit_comments/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
