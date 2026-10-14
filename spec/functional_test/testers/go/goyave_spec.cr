require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/create", "POST"),
  Endpoint.new("/product/{id}", "GET", [
    # `{id:[0-9]+}` — the regex is a constraint, not a value, and the
    # analyzer records none. Same rule as php/laminas `constraints`.
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/version", "GET"),
  # `api.Route([]string{"PUT", http.MethodPatch}, ...)`: one route per method.
  Endpoint.new("/api/users/{userID}", "PUT", [Param.new("userID", "", "path")]),
  Endpoint.new("/api/users/{userID}", "PATCH", [Param.new("userID", "", "path")]),
  Endpoint.new("/static/index.html", "GET"),
]

FunctionalTester.new("fixtures/go/goyave/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
