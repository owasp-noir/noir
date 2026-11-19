require "../../func_spec.cr"

# A workspace crate that depends on `poem-openapi` alone still holds poem
# routes, though a sibling crate is the one depending on `poem`.
expected_endpoints = [
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/poem_openapi_workspace/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
