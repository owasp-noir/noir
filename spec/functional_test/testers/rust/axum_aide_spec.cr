require "../../func_spec.cr"

# aide's `ApiRouter` (OpenAPI companion for axum). Covers `.api_route`,
# `.api_route_with` (path + method-router + transform closure), the
# `*_with` verb constructors (`post_with`), the multi-verb `get(h).head(h)`
# method-router, and `.nest_api_service("/api/v1", v1_router())` prefix
# composition through a same-file router-returning function.
expected_endpoints = [
  Endpoint.new("/health/ping", "GET"),
  Endpoint.new("/health/ping", "HEAD"),
  Endpoint.new("/admin/redrive", "POST"),
  Endpoint.new("/api/v1/app", "GET"),
  Endpoint.new("/api/v1/app", "POST"),
]

FunctionalTester.new("fixtures/rust/axum_aide/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
