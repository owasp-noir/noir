require "../../func_spec.cr"

# An inline `warp::path("api").and(a.or(b))` prefixes each alternative,
# whether let-bound or inline, and a prefix over a fn that only composes
# route fns reaches those fns. No bare prefix-only route is emitted.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/posts", "POST"),
  Endpoint.new("/v2/items", "GET"),
  Endpoint.new("/v2/tags", "DELETE"),
  Endpoint.new("/svc/todos", "GET"),
  Endpoint.new("/svc/todos", "POST"),
]

FunctionalTester.new("fixtures/rust/warp_prefix_compose/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
