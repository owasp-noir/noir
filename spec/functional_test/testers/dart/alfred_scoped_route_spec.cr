require "../../func_spec.cr"

# Both functions bind `r` to a different `app.route()` base; each call
# resolves against the nearest preceding binding.
expected_endpoints = [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/users/create", "POST"),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/list", "GET"),
  Endpoint.new("/posts/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/dart/alfred_scoped_route/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
