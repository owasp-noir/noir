require "../../func_spec.cr"

# `web::resource("/p").to(handler)` — the verb-less actix resource form
# (handler answers any method). Emitted as a single GET, with the enclosing
# `web::scope("/api")` prefix composed in and a closure handler supported.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/inline", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_resource_to/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
