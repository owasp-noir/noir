require "../../func_spec.cr"

# Covers chi's net/http registrations and the idiomatic REST "resource"
# pattern:
#   * r.MethodFunc("GET", "/health", h)  — method as the first string arg
#   * r.HandleFunc("/everything", h)     — matches every HTTP method (ANY)
#   * r.Mount("/todos", todosResource{}.Routes()) — struct value-method
#     router mounted under a prefix, with the body living in a sibling
#     file. The receiver type disambiguates two resources that both
#     expose a `Routes()` method (todos vs users).
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/submit", "POST"),
  # HandleFunc fans out across the full HTTP method set.
  Endpoint.new("/everything", "GET"),
  Endpoint.new("/everything", "POST"),
  Endpoint.new("/everything", "PUT"),
  Endpoint.new("/everything", "PATCH"),
  Endpoint.new("/everything", "DELETE"),
  Endpoint.new("/everything", "HEAD"),
  Endpoint.new("/everything", "OPTIONS"),
  # todosResource.Routes() mounted at /todos.
  Endpoint.new("/todos/", "GET"),
  Endpoint.new("/todos/", "POST"),
  Endpoint.new("/todos/{id}/", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/todos/{id}/", "DELETE", [Param.new("id", "", "path")]),
  # usersResource.Routes() mounted at /users — resolved to its own body
  # by receiver type, not the first `Routes()` method found.
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/{id}/", "PUT", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/go/chi_resource/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
