require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/books", "GET"),
  Endpoint.new("/books/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/books/new", "GET"),
  Endpoint.new("/books", "POST"),
  Endpoint.new("/books/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/books/:id", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/ruby/hanami/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
