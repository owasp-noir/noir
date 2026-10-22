require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/echo", "GET", [
    # roxygen `@param <name> <description>` — the trailing text is the
    # parameter's description, not a default value.
    Param.new("msg", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "body"),
    Param.new("password", "", "body"),
  ]),
  Endpoint.new("/users/:id/posts/:post_id", "GET", [
    Param.new("id", "", "path"),
    Param.new("post_id", "", "path"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "body"),
  ]),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/save/:key", "POST", [
    Param.new("key", "", "path"),
  ]),
  Endpoint.new("/direct", "GET"),
  Endpoint.new("/resource/:resource_id", "DELETE", [
    Param.new("resource_id", "", "path"),
  ]),
  # `req`/`res` are handed to the handler by plumber and `...` is R's
  # variadic marker, so `term` is the only thing a client actually sends.
  Endpoint.new("/search", "GET", [
    Param.new("term", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/r/plumber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
