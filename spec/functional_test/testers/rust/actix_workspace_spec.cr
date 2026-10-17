require "../../func_spec.cr"

# A Cargo workspace is one mount scope: `server` mounts a handler that lives
# in the sibling `api` crate, so per-crate scoping must not drop its prefix.
expected_endpoints = [
  Endpoint.new("/api/list", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_workspace/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
