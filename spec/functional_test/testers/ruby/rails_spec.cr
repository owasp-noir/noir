require "../../func_spec.cr"

extected_endpoints = [
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
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
]

FunctionalTester.new("fixtures/ruby/rails/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
