require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/api", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/create", "GET", [Param.new("body", "", "json")]),
  Endpoint.new("/form", "GET", [Param.new("form", "", "form")]),
  Endpoint.new("/auth", "GET", [Param.new("Authorization", "", "header"), Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/session", "GET", [Param.new("session_id", "", "cookie")]),
  Endpoint.new("/posts/:category/:id", "GET", [Param.new("category", "", "path"), Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/rust/rwf/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
