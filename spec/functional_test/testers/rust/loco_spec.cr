require "../../func_spec.cr"

# Modern Loco registers routes explicitly via the
# `Routes::new().prefix(...).add("/path", verb(handler))` builder. The
# controller-level prefix is composed onto every route, a single `.add`
# can fan out into several verbs, brace path params (`{id}`) are
# captured, and the Axum extractors in each handler signature surface as
# params.
expected_endpoints = [
  Endpoint.new("/api/posts", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/api/posts", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/api/posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/{id}", "PUT", [Param.new("id", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/api/posts/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/{id}/comments", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/login", "POST", [Param.new("form", "", "form")]),
  Endpoint.new("/api/posts/me", "GET", [Param.new("Authorization", "", "header")]),
]

FunctionalTester.new("fixtures/rust/loco/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
