require "../../func_spec.cr"

# Cross-function router composition. main.rs mounts builder fns from
# `routes/` via `.push()` / `.unshift()`; the analyzer must thread the
# `/api` base each builder is mounted under into the routes the builder
# returns — across files, through an intermediate `.hoop()`-only router,
# recursively (build_system_route -> build_user_route), and resolving a
# concatenated cross-module const path (PREFIX + "panel").
expected_endpoints = [
  Endpoint.new("/api", "GET"),
  Endpoint.new("/api/logs", "GET"),
  Endpoint.new("/api/system/users", "GET"),
  Endpoint.new("/api/admin/panel", "GET"),
]

FunctionalTester.new("fixtures/rust/salvo_crossfn/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_salvo"),
}).perform_tests
