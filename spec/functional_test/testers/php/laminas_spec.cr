require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/admin/users", "POST"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/reports/{reportId}", "GET", [Param.new("reportId", "", "path")]),
  Endpoint.new("/api/reports/{reportId}", "PATCH", [Param.new("reportId", "", "path")]),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("force", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/php/laminas/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
