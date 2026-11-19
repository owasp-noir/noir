require "../../func_spec.cr"

# `AppRoutes::..().prefix("/l-api")` prefixes the controllers added after
# it; one added before keeps its own path.
expected_endpoints = [
  Endpoint.new("/l-api/auth/register", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/l-api/auth/verify/{token}", "GET", [Param.new("token", "", "path")]),
  Endpoint.new("/l-api/auth/current", "GET"),
  Endpoint.new("/status/ping", "GET"),
]

FunctionalTester.new("fixtures/rust/loco_app_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_loco"),
}).perform_tests
