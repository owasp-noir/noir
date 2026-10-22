require "../../func_spec.cr"

# Loco: `cargo loco generate scaffold` registers member routes without a
# leading slash (`.add("{id}", get(h))`, older `":id"`) under a
# `.prefix("api/notes/")`. A slash-less `.add` off a non-`Routes` chain
# is still ignored.
expected_endpoints = [
  Endpoint.new("/api/notes", "GET"),
  Endpoint.new("/api/notes", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/api/notes/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/notes/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/notes/{id}", "PUT", [Param.new("id", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/api/notes/{id}", "PATCH", [Param.new("id", "", "path"), Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/rust/loco_scaffold/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_loco"),
}).perform_tests
