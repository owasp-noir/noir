require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/book/index", "GET"),
  Endpoint.new("/book/show", "GET"),
  Endpoint.new("/book/save", "POST"),
  Endpoint.new("/book/update", "PUT"),
  Endpoint.new("/book/update", "PATCH"),
  Endpoint.new("/book/delete", "DELETE"),
  Endpoint.new("/author/list", "GET"),
  Endpoint.new("/author/profile", "GET"),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/login", "POST"),
]

FunctionalTester.new("fixtures/groovy/grails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
