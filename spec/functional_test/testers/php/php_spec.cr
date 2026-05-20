require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/get.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/header.php", "GET", [
    Param.new("X-API-KEY", "", "header"),
    Param.new("param1", "", "query"),
  ]),
  Endpoint.new("/modern.php", "GET", [
    Param.new("id", "", "query"),
    Param.new("session_id", "", "cookie"),
    Param.new("AUTHORIZATION", "", "header"),
  ]),
  Endpoint.new("/modern.php", "POST", [
    Param.new("name", "", "form"),
    Param.new("avatar", "", "file"),
    Param.new("AUTHORIZATION", "", "header"),
  ]),
  Endpoint.new("/post.php", "GET"),
  Endpoint.new("/post.php", "POST", [
    Param.new("param1", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/request.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/request.php", "POST", [Param.new("param1", "", "form")]),
]

FunctionalTester.new("fixtures/php/php/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
