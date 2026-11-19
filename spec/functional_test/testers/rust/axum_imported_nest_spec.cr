require "../../func_spec.cr"

# `.nest(prefix, f())` where `f` is brought in with `use` (bare, or renamed
# with `as`), or lives in a workspace crate whose name is not its directory
# (`web-api` called as `web_api`, directory `api` named `acme_api`). The
# mounted fn is resolved through the imports, so its routes take the prefix.
# The utoipa `OpenApiRouter` nest resolves the same way.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/web/users", "GET"),
  Endpoint.new("/acme/orders", "GET"),
  Endpoint.new("/docs/readme", "GET"),
]

FunctionalTester.new("fixtures/rust/axum_imported_nest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
