require "../../func_spec.cr"

# `#[get("")]` registers a handler at the root of its scope. The path is the
# attribute's first literal even when empty, so a later `guard = ".."`,
# `name = ".."` or `method = ".."` string is not taken as the path.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/", "GET"),
  Endpoint.new("/a", "GET"),
  Endpoint.new("/a", "POST"),
  Endpoint.new("/b", "GET"),
  Endpoint.new("/c", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_empty_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
