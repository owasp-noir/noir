require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/upload", "POST"),
  Endpoint.new("/socket", "GET"), # WebSocket endpoint
  Endpoint.new("/test.html", "GET"),
  Endpoint.new("/style.css", "GET"),
  # `routes :web, "/admin" do resources "/articles", … end` expands to the
  # seven RESTful routes, each prefixed with the "/admin" scope.
  Endpoint.new("/admin/articles", "GET"),
  Endpoint.new("/admin/articles/new", "GET"),
  Endpoint.new("/admin/articles", "POST"),
  Endpoint.new("/admin/articles/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/articles/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/articles/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/articles/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/articles/:id", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/crystal/amber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
