require "../../func_spec.cr"

# Rocket's generic `#[route(...)]` attribute: the legacy verb-first form
# `#[route(GET, uri = "/p")]`, the modern `#[route("/p", method = POST)]`
# form (with `data = "<body>"`), and `#[get(...)]`. Custom non-HTTP
# methods (PROPFIND) are not emitted.
expected_endpoints = [
  Endpoint.new("/legacy", "GET"),
  Endpoint.new("/modern", "POST"),
  Endpoint.new("/with-data", "PUT", [Param.new("body", "", "body")]),
  Endpoint.new("/plain", "GET"),
]

FunctionalTester.new("fixtures/rust/rocket_route_macro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rocket"),
}).perform_tests
