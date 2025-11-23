require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/info", "GET", [
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/update", "POST", [
    Param.new("name", "", "form"),
    Param.new("auth", "", "cookie"),
    Param.new("X-API-Key", "", "header"),
    Param.new("Vary", "Origin", "header"),
  ]),
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/ws", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/v1/migration", "GET"),
  Endpoint.new("/update-put", "PUT"),
  Endpoint.new("/delete-item", "DELETE"),
  Endpoint.new("/multiline", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/fiber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
