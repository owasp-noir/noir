require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/foos/", "GET"),
  Endpoint.new("/foos/", "POST"),
  Endpoint.new("/foos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/foos/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/foos/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/go/pocketbase/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
