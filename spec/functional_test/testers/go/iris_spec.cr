require "../../func_spec.cr"

expected_endpoints = [
  # main.go
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("email", "", "form"),
  ]),
  # Path param type annotation stripped: {id:uint64} → {id}
  Endpoint.new("/users/{id}", "PUT"),
  Endpoint.new("/users/{id}", "DELETE"),
  Endpoint.new("/items/{id}", "PATCH"),
  Endpoint.new("/health", "OPTIONS"),
  Endpoint.new("/health", "HEAD"),
  # app.Any("/any", ...) expands to all HTTP methods
  Endpoint.new("/any", "GET"),
  Endpoint.new("/any", "POST"),
  Endpoint.new("/any", "PUT"),
  Endpoint.new("/any", "DELETE"),
  Endpoint.new("/any", "PATCH"),
  Endpoint.new("/any", "OPTIONS"),
  Endpoint.new("/any", "HEAD"),
  # routes/api.go (Party-based grouping: /api/v1/...)
  Endpoint.new("/api/v1/users", "GET", [
    Param.new("search", "", "query"),
  ]),
  Endpoint.new("/api/v1/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/v1/profile", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/v1/files/{file}", "GET"),
]

FunctionalTester.new("fixtures/go/iris/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
