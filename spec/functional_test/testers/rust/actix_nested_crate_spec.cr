require "../../func_spec.cr"

# The root package depends on actix-web and so does the workspace listing;
# the member crate under `lib/` does not, so its files are not actix source.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_nested_crate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
