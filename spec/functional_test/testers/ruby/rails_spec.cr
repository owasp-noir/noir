require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/posts/1", "GET", [
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PATCH", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/posts/1/search", "QUERY"),
  Endpoint.new("/search", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/filter", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/articles", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("alpha", "", "form"),
    Param.new("beta", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PUT", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PATCH", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/service-worker", "GET"),
  Endpoint.new("/manifest", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
