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
  Endpoint.new("/static/index.html", "GET"),
]

FunctionalTester.new("fixtures/go/goyave/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
