require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/customer", "POST", [
    Param.new("input", "", "body"),
  ]),
  Endpoint.new("/users/<id>", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/<category>/<id>", "GET", [
    Param.new("category", "", "path"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/search?<query>&<limit>", "GET", [
    Param.new("query", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/filter?<name>&<age>&<active>", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
    Param.new("active", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("user", "", "body"),
  ]),
  Endpoint.new("/products/<id>", "PUT", [
    Param.new("id", "", "path"),
    Param.new("product", "", "body"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("credentials", "", "body"),
  ]),
  Endpoint.new("/items/<id>?<version>", "POST", [
    Param.new("id", "", "path"),
    Param.new("version", "", "query"),
    Param.new("item", "", "body"),
  ]),
  Endpoint.new("/session", "GET", [
    Param.new("session_id", "", "cookie"),
    Param.new("user_token", "", "cookie"),
  ]),
  Endpoint.new("/profile", "GET", [
    Param.new("auth_token", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/rust/rocket/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
