require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/hey", "GET"),
  # Bare `Query<T>` / `Form<T>` imported from `ntex::web::types`.
  Endpoint.new("/search", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/files/{all}", "GET", [
    Param.new("all", "", "path"),
  ]),
  # Handlers mounted through a tuple `.service((...))` under a scope.
  Endpoint.new("/api/v1/items/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/v1/login", "POST", [
    Param.new("form", "", "form"),
  ]),
  Endpoint.new("/api/v1/sessions/{sid}", "DELETE", [
    Param.new("sid", "", "path"),
    Param.new("X-Session-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/stats", "GET", [
    Param.new("query", "", "query"),
  ]),
  # Nested tuple scopes in a `.configure`d fn (src/appconfig.rs).
  Endpoint.new("/products", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/products", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/products/{product_id}", "GET", [
    Param.new("product_id", "", "path"),
  ]),
  Endpoint.new("/products/{product_id}", "DELETE", [
    Param.new("product_id", "", "path"),
  ]),
  Endpoint.new("/products/{product_id}/parts/{part_id}", "GET", [
    Param.new("product_id", "", "path"),
    Param.new("part_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/rust/ntex/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
