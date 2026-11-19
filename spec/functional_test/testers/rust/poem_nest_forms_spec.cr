require "../../func_spec.cr"

# Nest prefixes reach a `let`-bound sub-router, a sub-router fn of another
# module, every API struct of an `OpenApiService::new((A, B), ..)` tuple,
# and compose with `#[OpenApi(prefix_path = "..")]`.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/admin/panel", "GET"),
  Endpoint.new("/api/pets", "GET"),
  Endpoint.new("/api/store/orders", "POST"),
]

FunctionalTester.new("fixtures/rust/poem_nest_forms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
