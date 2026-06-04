require "../../func_spec.cr"

# poem-openapi `#[oai(path, method)]` handlers nested under `/api` via
# `Route::new().nest("/api", api_service)` where
# `api_service = OpenApiService::new(Api, ...)`. The analyzer composes the
# nest prefix with each handler's local path, resolving the service variable
# back to its `impl Api` block. The `swagger_ui()` mounted at `/` does not
# map to the API impl, so the handlers don't double up at the root.
expected_endpoints = [
  Endpoint.new("/api/hello", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/poem_nest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
