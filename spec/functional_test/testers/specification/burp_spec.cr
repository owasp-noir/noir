require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("q", "alice", "query"),
    Param.new("role", "admin", "query"),
    Param.new("User-Agent", "Mozilla/5.0", "header"),
    Param.new("Accept", "application/json", "header"),
    Param.new("X-Trace-Id", "42", "header"),
    Param.new("session", "abc123", "cookie"),
    Param.new("csrf", "xyz789", "cookie"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("user", "admin", "form"),
    Param.new("pass", "hunter2", "form"),
  ]),
  Endpoint.new("/health", "GET", [
    Param.new("X-Plain", "yes", "header"),
  ]),
]

FunctionalTester.new("fixtures/specification/burp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
