require "../../func_spec.cr"

extected_endpoints = [
  # PostsController endpoints (mapped without /posts prefix)
  Endpoint.new("/", "GET"),
  Endpoint.new("/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/new", "GET"),
  Endpoint.new("/", "POST"),
  Endpoint.new("/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/:id", "DELETE", [Param.new("id", "", "path")]),
  # API controller endpoints
  Endpoint.new("/users", "GET"),
  Endpoint.new("/health_check", "GET"),
  # Function-style handler
  Endpoint.new("/dashboard", "GET"),
]

FunctionalTester.new("fixtures/rust/loco/", {
  :techs     => 2,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests