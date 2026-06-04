require "../../func_spec.cr"

# RWF sub-engine mounting: `engine!("/admin" => engine)` mounts an engine
# and is NOT itself an endpoint; the engine's child routes inherit the
# `/admin` prefix.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/admin/index", "GET"),
  Endpoint.new("/admin/about", "GET"),
]

FunctionalTester.new("fixtures/rust/rwf_engine/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rwf"),
}).perform_tests
