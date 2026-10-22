require "../../func_spec.cr"

# Two-level cross-file nest: `main` nests `routes::api_router()` under
# `/api/v1`, which in turn nests `users::router()` under `/users`. The
# inner `.nest("/users", …)` is not a root mount, so the users routes
# appear only under `/api/v1/users` — no prefix-less `/users/...` copies.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/api/v1/users/", "GET"),
  Endpoint.new("/api/v1/users/", "POST"),
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/:id/avatar", "POST", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/axum_crossfile_nest_chain/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
