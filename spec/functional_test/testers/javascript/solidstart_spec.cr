require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  # `blog.tsx` sits beside `blog/`, so it is the layout; `(blog).tsx` is
  # the renamed index.
  Endpoint.new("/blog", "GET"),
  Endpoint.new("/blog/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  # `(auth)` is a route group — stripped from the URL.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/{404}", "GET", [Param.new("404", "", "path")]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/solidstart/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
