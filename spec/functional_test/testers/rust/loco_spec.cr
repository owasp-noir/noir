require "../../func_spec.cr"

expected_endpoints = [
  # PostsController endpoints (mapped without /posts prefix)
  Endpoint.new("/", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/new", "GET"),
  Endpoint.new("/", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/:id", "PATCH", [Param.new("id", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/:id", "DELETE", [Param.new("id", "", "path")]),
  # API controller endpoints
  Endpoint.new("/users", "GET", [Param.new("Authorization", "", "header")]),
  Endpoint.new("/health_check", "GET"),
  # Function-style handler
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/login", "POST", [Param.new("form", "", "form")]),
]

FunctionalTester.new("fixtures/rust/loco/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
