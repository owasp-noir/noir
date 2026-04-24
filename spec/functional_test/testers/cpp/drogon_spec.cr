require "../../func_spec.cr"

expected_endpoints = [
  # main.cpp — path-based registerHandler with lambdas
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Path param type annotation stripped: {id:int} → {id}
  Endpoint.new("/items/{id}", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/items/{id}", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  # controllers/UsersController.cpp — PATH_LIST_BEGIN with PATH_ADD
  Endpoint.new("/api/users", "GET", [
    Param.new("search", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/users/{id}", "GET"),
  Endpoint.new("/api/users/{id}", "PUT"),
  Endpoint.new("/api/users/{id}", "DELETE"),
  Endpoint.new("/api/users/{id}/profile", "GET", [
    Param.new("X-API-Token", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/cpp/drogon/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
