require "../../func_spec.cr"

# `routes.forEach((route) => fastify.route(route))` over an imported table
# and `for (const r of localRoutes) fastify.route(r)` over a same-file one.
# A table nothing registers is not served.
expected_endpoints = [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/api/cars", "GET", [Param.new("make", "", "query")]),
  Endpoint.new("/api/cars", "POST", [Param.new("title", "", "json"), Param.new("brand", "", "json")]),
  Endpoint.new("/api/cars/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/local/a", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/local/b", "PUT"),
]

FunctionalTester.new("fixtures/javascript/fastify_route_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
