require "../../func_spec.cr"

# A file is only read as Vert.x when it references `io.vertx`. The old
# `Router`/`vertx` substring gate let `com.acme.web.Router` files through,
# where `HttpRequest.GET("/x")`, `Request.Post("/x")` and `Map.put("/x", ..)`
# became phantom routes next to the one real Vert.x file.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
]

FunctionalTester.new("fixtures/java/vertx_non_vertx_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
