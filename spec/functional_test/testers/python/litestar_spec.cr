require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/users", "POST", [Param.new("data", "", "json")]),
  Endpoint.new("/users/{user_id}", "PUT", [Param.new("user_id", "", "path"), Param.new("data", "", "json")]),
  Endpoint.new("/users/{user_id}", "DELETE", [Param.new("user_id", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  Endpoint.new("/headers", "GET", [Param.new("X-Token", "", "header")]),
  Endpoint.new("/cookies", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{item_id}", "GET", [Param.new("item_id", "", "path")]),
]

FunctionalTester.new("fixtures/python/litestar/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
