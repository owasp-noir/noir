require "../../func_spec.cr"

# Warp: a let-bound prefix filter (`let api = warp::path("api").and(
# warp::path("v1"))`) mounting route lets via `api.and(list.or(create)…)`
# prefixes those routes and is not itself a `GET /api/v1` route. Untyped
# `warp::body::json()` / `warp::body::form()` (type inferred from the
# closure) still yield a body param.
expected_endpoints = [
  Endpoint.new("/api/v1/todos", "GET", [Param.new("ListOptions", "", "query")]),
  Endpoint.new("/api/v1/todos", "POST", [Param.new("body", "", "json"), Param.new("authorization", "", "header")]),
  Endpoint.new("/api/v1/todos/:param", "PUT", [Param.new("param", "", "path"), Param.new("body", "", "form")]),
  Endpoint.new("/api/v1/todos/:param", "DELETE", [Param.new("param", "", "path"), Param.new("session", "", "cookie")]),
  Endpoint.new("/hello/:param", "GET", [Param.new("param", "", "path")]),
]

FunctionalTester.new("fixtures/rust/warp_let_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
