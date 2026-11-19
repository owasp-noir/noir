require "../../func_spec.cr"

# `#[rocket::get("/x")]` is a Rocket route like `#[get("/x")]`; another
# crate's `#[other_web::get]` is not.
expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "PATCH", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/rocket_qualified_attr/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_rocket"),
}).perform_tests
