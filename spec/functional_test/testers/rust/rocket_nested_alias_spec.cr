require "../../func_spec.cr"

# A route collector re-exported through a nested `use crate::{ events::{
# build_routes as events_routes } }` group. The alias target is recorded
# relative to the inner group (`build_routes`), so the `.mount("/events",
# events_routes())` resolution must match it as a unique module-qualified
# suffix to apply the /events prefix (vaultwarden's core_events_routes shape).
expected_endpoints = [
  Endpoint.new("/events/collect", "POST"),
]

FunctionalTester.new("fixtures/rust/rocket_nested_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rocket"),
}).perform_tests
