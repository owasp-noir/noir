require "../../func_spec.cr"

# Tide README shape: `let Animal { name, legs } = req.body_json().await?;`
# names the body type in the destructuring pattern, not an annotation.
expected_endpoints = [
  Endpoint.new("/orders/shoes", "POST", [Param.new("Animal", "", "json")]),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path"), Param.new("X-Token", "", "header")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path"), Param.new("X-Token", "", "header")]),
  Endpoint.new("/api/items", "GET", [Param.new("Page", "", "query")]),
  Endpoint.new("/api/items/:item_id", "PUT", [Param.new("item_id", "", "path")]),
  Endpoint.new("/static", "GET"),
]

FunctionalTester.new("fixtures/rust/tide_destructure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_tide"),
}).perform_tests
