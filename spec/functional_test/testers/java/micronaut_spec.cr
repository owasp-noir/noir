require "../../func_spec.cr"

books_ws_endpoint = Endpoint.new("/api/books/ws/{topic}/{username}", "GET", [
  Param.new("topic", "", "path"),
  Param.new("username", "", "path"),
])
books_ws_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("/books", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/books/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/books/popular", "GET"),
  Endpoint.new("/books/featured", "GET"),
  Endpoint.new("/books/admin/stats", "GET"),
  Endpoint.new("/books/export", "GET"),
  Endpoint.new("/books/search", "GET", [
    Param.new("q", "all", "query"),
    Param.new("X-Client", "", "header"),
  ]),
  Endpoint.new("/books/constants", "GET", [
    Param.new("code", "none", "query"),
    Param.new("X-Code", "", "header"),
  ]),
  Endpoint.new("/books/filter", "GET", [
    Param.new("author", "", "query"),
    Param.new("year", "", "query"),
  ]),
  Endpoint.new("/books/template", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/books/paged", "GET", [
    Param.new("author", "", "query"),
    Param.new("year", "", "query"),
  ]),
  Endpoint.new("/books/calendar/{month}", "GET", [
    Param.new("month", "", "path"),
  ]),
  Endpoint.new("/books/interface/{isbn}", "GET", [
    Param.new("isbn", "", "path"),
    Param.new("edition", "", "query"),
  ]),
  Endpoint.new("/css/*.css", "GET"),
  Endpoint.new("/images/**", "GET"),
  Endpoint.new("/mn/status", "GET"),
  books_ws_endpoint,
  Endpoint.new("/books", "POST", [
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
  Endpoint.new("/books/forms", "POST", [
    Param.new("title", "", "form"),
    Param.new("author", "", "form"),
    Param.new("year", "", "form"),
  ]),
  Endpoint.new("/books/attachment", "POST", [
    Param.new("file", "", "form"),
  ]),
  Endpoint.new("/books/scalar", "POST", [
    Param.new("isbn", "", "json"),
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/books/login", "POST", [
    Param.new("username", "", "query"),
    Param.new("pwd", "", "query"),
  ]),
  Endpoint.new("/books/interface", "POST", [
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
  Endpoint.new("/books/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
  Endpoint.new("/books/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/books/constants", "DELETE", [
    Param.new("session-id", "", "cookie"),
  ]),
  Endpoint.new("/books/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/java/micronaut/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
