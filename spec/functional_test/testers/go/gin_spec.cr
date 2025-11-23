require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/public/secret.html", "GET"),
  Endpoint.new("/group/users", "GET"),
  Endpoint.new("/group/v1/migration", "GET"),
  Endpoint.new("/mixed-get", "GET"),
  Endpoint.new("/mixed-post", "POST", [
    Param.new("field1", "", "form"),
  ]),
  Endpoint.new("/mixed-put", "PUT"),
  Endpoint.new("/mixed-delete", "DELETE"),
  Endpoint.new("/multiline", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/gin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
