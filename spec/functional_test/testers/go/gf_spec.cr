require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/upload", "GET", [
    Param.new("TestFile", "", "form"),
  ]),
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/api/users", "GET", [
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/api/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "json"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/api/v1/migration", "GET"),
  Endpoint.new("/api/v1/update", "PUT"),
  Endpoint.new("/mixed/get", "GET"),
  Endpoint.new("/mixed/post", "POST", [
    Param.new("field1", "", "form"),
  ]),
  Endpoint.new("/mixed/delete", "DELETE"),
  Endpoint.new("/multi/line", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/gf/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
