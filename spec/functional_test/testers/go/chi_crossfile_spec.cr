require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/api/settings/", "GET", [Param.new("Authorization", "", "header")]),
  Endpoint.new("/api/settings/", "PUT", [Param.new("theme", "", "form")]),
]

FunctionalTester.new("fixtures/go/chi_crossfile/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
