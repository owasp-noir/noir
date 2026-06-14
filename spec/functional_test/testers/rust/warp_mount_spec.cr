require "../../func_spec.cr"

# Cross-fn prefix composition: `warp::path("api").and(backend())` mounts a
# sibling filter-returning fn under `/api`. The mounted fn's routes inherit
# the prefix, the prefix-only stub is NOT emitted as a bare `/api`, the
# `String` segment in `path!` becomes a `{param}`, and an un-mounted leaf
# whose `.and(with_state())` extractor carries no path is left untouched.
expected_endpoints = [
  Endpoint.new("/api/socket/:param", "GET", [
    Param.new("param", "", "path"),
  ]),
  Endpoint.new("/api/text/:param", "GET", [
    Param.new("param", "", "path"),
  ]),
  Endpoint.new("/api/stats", "GET"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/rust/warp_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_warp"),
}).perform_tests
