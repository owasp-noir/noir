require "../../func_spec.cr"

# actix-web method-less route constructors: `web::route()` narrowed by a
# `guard::<Verb>()`, `web::method(Method::PATCH)`, and a bare
# `web::route()` that answers every method.
expected_endpoints = [
  Endpoint.new("/path", "GET"),
  Endpoint.new("/a", "POST"),
  Endpoint.new("/b", "PATCH"),
  Endpoint.new("/c", "GET"),
  Endpoint.new("/c", "POST"),
  Endpoint.new("/c", "PUT"),
  Endpoint.new("/c", "PATCH"),
  Endpoint.new("/c", "DELETE"),
  Endpoint.new("/c", "OPTIONS"),
  Endpoint.new("/c", "HEAD"),
  Endpoint.new("/d", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_route_guard/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
