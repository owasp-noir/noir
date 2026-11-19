require "../../func_spec.cr"

# `app.at("/api").nest(api)` prefixes the routes registered on the
# `let mut api = tide::new()` server, and only those.
expected_endpoints = [
  Endpoint.new("/api/hello", "GET"),
  Endpoint.new("/api/goodbye", "POST"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/rust/tide_nest_let/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_tide"),
}).perform_tests
