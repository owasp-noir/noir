require "../../func_spec.cr"

expected_endpoints = [
  # `{**catch-all}` / `{*rest}` match any remaining path.
  Endpoint.new("/api/*", "GET"),
  Endpoint.new("/api/*", "POST"),
  Endpoint.new("/orders/{id}", "ANY", [
    Param.new("id", "", "path"),
    Param.new("version", "", "query"),
    Param.new("X-Tenant", "", "header"),
  ]),
  # Built in code with `new RouteMatch { ... }`.
  Endpoint.new("/admin/*", "DELETE"),
  # Target-typed `Match = new() { ... }`.
  Endpoint.new("/reports", "ANY"),
  Endpoint.new("/status/{name}", "PATCH", [Param.new("name", "", "path")]),
]

FunctionalTester.new("fixtures/specification/yarp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
