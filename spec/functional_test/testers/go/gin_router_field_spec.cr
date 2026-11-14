require "../../func_spec.cr"

# Routes registered on a struct field the package declares with a gin router
# type, whatever the field is called (#3591): `s.router`, `s.engine`, a
# `s.api` group assigned in one method and used in another (and in another
# file), an `IRouter` field, a `.Group(...)` chain off a field. The import is
# aliased (`g`). Lookups on non-router fields (`c.Request.Get`, `s.client`,
# `s.cache`, `s.db`) and a `router` field of another type in another package
# stay out.
expected_endpoints = [
  Endpoint.new("/lower", "GET"),
  Endpoint.new("/upper", "GET"),
  Endpoint.new("/engine", "POST"),
  Endpoint.new("/api/x", "GET"),
  Endpoint.new("/chain/z", "GET"),
  Endpoint.new("/v1/y", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/v1/w", "PUT"),
  Endpoint.new("/admin/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/direct", "GET", [Param.new("page", "", "query")]),
]

FunctionalTester.new("fixtures/go/gin_router_field/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
