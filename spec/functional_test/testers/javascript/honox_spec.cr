require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/{id}", "DELETE", [Param.new("id", "", "path"), Param.new("X-Api-Key", "", "header")]),
  # `(marketing)` is a group.
  Endpoint.new("/about", "GET"),
  Endpoint.new("/docs/{slug}", "GET", [Param.new("slug", "", "path")]),
  # A default-exported `new Hono()` app is mounted at its module's path.
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/admin/reindex/:index", "POST", [Param.new("index", "", "path")]),
  # Not routes: `_renderer`, `_middleware`, `_404`, the `$counter` island
  # and everything outside `app/routes/`.
]

FunctionalTester.new("fixtures/javascript/honox/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
