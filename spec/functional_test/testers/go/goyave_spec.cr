require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/create", "POST"),
  Endpoint.new("/product/{id}", "GET", [
    Param.new("id", "[0-9]+", "path"),
  ]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/version", "GET"),
  Endpoint.new("/static/index.html", "GET"),
]

FunctionalTester.new("fixtures/go/goyave/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
