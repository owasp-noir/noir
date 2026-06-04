require "../../func_spec.cr"

# utoipa-axum routing: `#[utoipa::path(method, path)]` handlers wired up with
# `OpenApiRouter::new().routes(routes!(mod::handler))` and mounted via
# `.nest("/api/v1/x", mod_routes::create_routes())`. The analyzer composes
# each handler's attribute path with the cross-file nest prefix, threading
# through a recursively nested collector (/api/v1/users + /tokens) and the
# `method(get, post)` multi-verb form.
expected_endpoints = [
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users/{id}", "GET"),
  Endpoint.new("/api/v1/users/tokens", "GET"),
  Endpoint.new("/api/v1/admin/dashboard", "GET"),
  Endpoint.new("/api/v1/admin/dashboard", "POST"),
]

FunctionalTester.new("fixtures/rust/axum_utoipa/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
