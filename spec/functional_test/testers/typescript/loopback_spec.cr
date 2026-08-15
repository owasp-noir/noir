require "../../func_spec.cr"

expected_endpoints = [
  # `@param.query.*` shortcuts.
  Endpoint.new("/products", "GET", [
    Param.new("limit", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  # `@param.path.string('id')` + LoopBack's OpenAPI-style `{id}` path.
  Endpoint.new("/products/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  # `@requestBody()` — always a single generic `body` param.
  Endpoint.new("/products", "POST", [
    Param.new("body", "", "body"),
  ]),
  # Decorator stacking: `@authenticate`/`@authorize` sit between the
  # route decorator and the method signature and must not break param
  # extraction.
  Endpoint.new("/products/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/products/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/products/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # `id` has no `@param.path` decorator — recovered from the `{id}` URL
  # placeholder fallback — plus `@param.header.string(...)`.
  Endpoint.new("/products/{id}/reviews", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-api-key", "", "header"),
  ]),
  # `@param.array('tags', 'query', ...)`.
  Endpoint.new("/products/search", "GET", [
    Param.new("tags", "", "query"),
  ]),
  # Generic `@operation('get', '/path', spec)` escape hatch.
  Endpoint.new("/products/count", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/loopback/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
