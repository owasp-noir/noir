require "../../func_spec.cr"

# `main` mounts `routes::config` under `/api`; that fn mounts
# `users::config` under `/users` and `admin::admin_routes` with no scope.
# Both inner fns inherit `/api`, and the same-named `users::config` is not
# also mounted at `/api` on its own (the endpoint count pins that).
expected_endpoints = [
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/api/users/list", "GET"),
  Endpoint.new("/api/users/manual", "GET"),
  Endpoint.new("/api/stats", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_nested_configure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
