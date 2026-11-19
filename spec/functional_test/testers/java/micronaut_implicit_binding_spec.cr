require "../../func_spec.cr"

# An argument with no binding annotation that is not a URI variable binds
# the query string, or a body property on a verb that carries a body
# (Java and Kotlin controllers).
q = ->(names : Array(String)) { names.map { |name| Param.new(name, "", "query") } }
login = [Param.new("username", "", "json"), Param.new("password", "", "json")]

expected_endpoints = [
  Endpoint.new("/books/search", "GET", q.call(%w[title author max])),
  Endpoint.new("/books/search-explicit", "GET", q.call(%w[title author max])),
  Endpoint.new("/books/{id}/pages", "GET", [Param.new("id", "", "path"), Param.new("from", "", "query")]),
  Endpoint.new("/books/login", "POST", login),
  Endpoint.new("/kt-books/search", "GET", q.call(%w[title author max])),
  Endpoint.new("/kt-books/search-explicit", "GET", q.call(%w[title author])),
  Endpoint.new("/kt-books/login", "POST", login),
]

FunctionalTester.new("fixtures/java/micronaut_implicit_binding/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
