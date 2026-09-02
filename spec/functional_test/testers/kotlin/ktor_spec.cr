require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/extension", "GET"),
  Endpoint.new("/extension/method", "POST"),
  Endpoint.new("/extension/query-method", "QUERY"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/search", "QUERY", [
    Param.new("body", "SearchRequest", "json"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/items", "QUERY"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/search", "QUERY"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [Param.new("body", "SubmitData", "json")]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/partial/{resourceId}", "PATCH", [
    Param.new("resourceId", "", "path"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/check/{id}", "HEAD", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/settings", "OPTIONS"),
  # Documented with the OpenAPI DSL: one GET route, and no QUERY route per
  # documented query parameter.
  Endpoint.new("/stream-bytes", "GET"),
  # Ktor's placeholder decorations describe the segment, not the parameter:
  # the handler reads `call.parameters["segments"]`, so `segments...` was
  # never a name anything could match. `{...}` is anonymous and names none.
  Endpoint.new("/listing/{segments...}", "GET", [
    Param.new("segments", "", "path"),
  ]),
  Endpoint.new("/optional/{slug?}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/anonymous/{...}", "GET"),
  # The literal opens the placeholder itself and interpolates only the name,
  # so the interpolation must not add a second pair of braces.
  Endpoint.new("/interpolated/{tail...}", "GET", [
    Param.new("tail", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/ktor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
