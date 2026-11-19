require "../../func_spec.cr"

# `web::scope("/api").configure(web_api::config)` where `web_api` is the
# workspace crate `web-api`: its routes keep the `/api` prefix.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/stats", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_hyphen_crate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
