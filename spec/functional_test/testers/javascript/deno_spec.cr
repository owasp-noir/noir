require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/books/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/authors/:name", "POST", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("x-api-key", "", "header"),
    Param.new("username", "", "json"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/metrics", "GET"),
  Endpoint.new("/items/:sku", "GET", [
    Param.new("sku", "", "path"),
  ]),
  # Same `match` alias declared in two blocks for different patterns.
  Endpoint.new("/orders/:id", "GET"),
  Endpoint.new("/invoices/:id", "POST"),
  # Negated `if (!m)` guard followed by a method branch.
  Endpoint.new("/carts/:id", "DELETE"),
]

FunctionalTester.new("fixtures/javascript/deno/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
