require "../../func_spec.cr"

# `r.Mount("/todos", todos.Resource{}.Routes())` with the resource in its own
# package, bound to a variable first (`pr := &posts.Resource{}`, `var tr
# todos.Resource`) or held in a struct field (`a.users.Routes()`), keeps the
# mount prefix. So does a sub-router mounted by name in a function whose
# `r.Route` closure redeclares `r`.
expected_endpoints = [
  Endpoint.new("/local/", "GET"),
  Endpoint.new("/todos/", "GET"),
  Endpoint.new("/todos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/todos-var/", "GET"),
  Endpoint.new("/todos-var/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/", "GET"),
  Endpoint.new("/admin/accounts", "GET"),
]

FunctionalTester.new("fixtures/go/chi_mount_resource_pkg/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
