require "../../func_spec.cr"

# `.nest("/admin", admin::routes())` names admin.rs's `routes`, not the
# same-named fn in main.rs, so main.rs's own routes stay unprefixed.
# `twice()` is nested under two prefixes and keeps its bare path; inline
# nests compose outermost first.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/after", "GET"),
  Endpoint.new("/api/inline", "GET"),
  Endpoint.new("/api/deep/d", "GET"),
  Endpoint.new("/panel", "GET"),
  Endpoint.new("/t", "GET"),
]

FunctionalTester.new("fixtures/rust/poem_nest_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
