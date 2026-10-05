require "../../func_spec.cr"

# Code-first HTTP triggers ship without `function.json`. Each app takes its
# route prefix from the nearest `host.json`: `csharp` keeps the `api` default,
# `python` disables it, `node` sets `v1`.
expected_endpoints = [
  # C# isolated worker + in-process
  Endpoint.new("/api/products/{id}", "GET"),
  Endpoint.new("/api/products", "POST"),
  Endpoint.new("/api/products", "PUT"),
  Endpoint.new("/api/Health", "ANY"),
  Endpoint.new("/api/ListOrders", "GET"),
  Endpoint.new("/api/orders/{id}", "PATCH"),
  # Python v2
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/orders", "POST"),
  Endpoint.new("/orders", "PUT"),
  Endpoint.new("/Status", "ANY"),
  Endpoint.new("/items/{id}", "GET"),
  Endpoint.new("/items/{id}", "DELETE"),
  # Node v4
  Endpoint.new("/v1/products/{id}", "GET"),
  Endpoint.new("/v1/hello", "GET"),
  Endpoint.new("/v1/hello", "POST"),
  Endpoint.new("/v1/health", "GET"),
  Endpoint.new("/v1/orders", "POST"),
  Endpoint.new("/v1/orders", "PUT"),
  Endpoint.new("/v1/orders/{id}", "DELETE"),
]

FunctionalTester.new("fixtures/specification/azure_functions_code_first/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
