require "../../func_spec.cr"

# A view without its own `request_method` takes the verbs of the
# `add_route(..., request_method=...)` it binds to; a view that declares
# one keeps it.
expected_endpoints = [
  Endpoint.new("/things", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/things/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/things/{id}/patch", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/show", "GET"),
  Endpoint.new("/show", "HEAD"),
]

FunctionalTester.new("fixtures/python/pyramid_route_predicate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
