require "../../func_spec.cr"

# A nest prefix reaches the routers merged under it: a `let`-bound or
# inline `Router::new().merge(mod::router())` nested by name or in place, and
# a same-file fn nested under `/v2` that merges other same-file router fns.
# A router fn merged at the root stays at the root.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/posts", "GET"),
  Endpoint.new("/api/v1/posts", "POST"),
  Endpoint.new("/inline/tags", "GET"),
  Endpoint.new("/v2/orders", "GET"),
  Endpoint.new("/v2/items", "GET"),
]

FunctionalTester.new("fixtures/rust/axum_merge_nest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
