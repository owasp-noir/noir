require "../../func_spec.cr"

# Any() expands to all seven HTTP methods for /health.
any_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]
any_endpoints = any_methods.map { |m| Endpoint.new("/health", m) }

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/group/users", "GET"),
  Endpoint.new("/group/v1/migration", "GET"),
  Endpoint.new("/public/index.html", "GET"),
] + any_endpoints

FunctionalTester.new("fixtures/go/hertz/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
