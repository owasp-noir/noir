require "../../func_spec.cr"

expected_endpoints = [
  # Verb resolved from `use <- wisp.require_method(req, Get)`.
  Endpoint.new("/", "GET"),
  # `["about"] | ["info"]` — one arm, two paths.
  Endpoint.new("/about", "GET"),
  Endpoint.new("/info", "GET"),
  # Verbs resolved by following the arm into another module's
  # `case req.method`.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "body"),
    Param.new("email", "", "body"),
  ]),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-api-token", "", "header"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("x-api-token", "", "header"),
  ]),
  Endpoint.new("/search", "GET"),
  # `wisp.serve_static` only serves GET.
  Endpoint.new("/static/*", "GET"),
  # The `case path, method` subject order, from the mounted sub-router.
  # The parent's `["posts", ..]` arm emits nothing, because the
  # sub-router matches these same absolute paths itself.
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "body"),
    Param.new("content", "", "body"),
  ]),
  Endpoint.new("/posts/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/:post_id/comments", "GET", [
    Param.new("post_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/gleam/wisp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
