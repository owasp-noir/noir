require "../../func_spec.cr"

# A regex-constrained `:id<\d+>` segment is the `{id}` param, and a
# module-qualified `payload::Json<T>` extractor is still a JSON body.
expected_endpoints = [
  Endpoint.new("/items/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/pets", "POST", [Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/rust/poem_segments/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_poem"),
}).perform_tests
