require "../../func_spec.cr"

# RWF registration shapes beyond the plain `route!` macro:
#   * `route!` with a multi-verb `handle` (GET + POST),
#   * the `.route(...)` method form,
#   * `crud!` / `rest!` expanding into the six-route REST surface with an
#     `:id` member param, and
#   * a scoped controller path (`controllers::Upload`).
def rest_surface(base)
  [
    Endpoint.new(base, "GET"),
    Endpoint.new(base, "POST"),
    Endpoint.new("#{base}/:id", "GET", [Param.new("id", "", "path")]),
    Endpoint.new("#{base}/:id", "PUT", [Param.new("id", "", "path")]),
    Endpoint.new("#{base}/:id", "PATCH", [Param.new("id", "", "path")]),
    Endpoint.new("#{base}/:id", "DELETE", [Param.new("id", "", "path")]),
  ]
end

expected_endpoints = [
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/upload", "GET"),
] + rest_surface("/api/users") + rest_surface("/api/posts")

FunctionalTester.new("fixtures/rust/rwf_rest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
