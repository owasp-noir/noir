require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/books", "GET"),
  Endpoint.new("/books/:id", "GET"),
  Endpoint.new("/books/new", "GET"),
  Endpoint.new("/books", "POST"),
  Endpoint.new("/books/:id", "PATCH"),
  Endpoint.new("/books/:id", "DELETE"),
]

FunctionalTester.new("fixtures/ruby_hanami/", {
  :techs     => 1,
  :endpoints => 6,
}, extected_endpoints).test_all
