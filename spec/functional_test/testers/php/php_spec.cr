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
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/post.php", "GET"),
  Endpoint.new("/post.php", "POST", [
    Param.new("param1", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/request.php", "GET", [Param.new("param1", "", "query")]),
  Endpoint.new("/request.php", "POST", [Param.new("param1", "", "form")]),
  # repeated.php exercises the order-preserving param dedup path inside the
  # pure PHP analyzer (same (name, param_type) appears via superglobal +
  # filter_input, and via COOKIE which populates both lists). The dedup
  # helper must keep first-seen order and produce exactly one Param per
  # (name, type) on the resulting pseudo-endpoints.
  Endpoint.new("/repeated.php", "GET", [
    Param.new("id", "", "query"),
    Param.new("token", "", "cookie"),
  ]),
  Endpoint.new("/repeated.php", "POST", [
    Param.new("data", "", "form"),
    Param.new("token", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/php/php/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
