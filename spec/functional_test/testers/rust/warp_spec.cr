require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/:param", "GET", [
    Param.new("param", "", "path"),
  ]),
  Endpoint.new("/users", "POST"),
]

FunctionalTester.new("fixtures/rust/warp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
