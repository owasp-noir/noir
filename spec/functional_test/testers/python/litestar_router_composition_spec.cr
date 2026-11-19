require "../../func_spec.cr"

# Routers nested in routers (`nested.py`, the Litestar docs example) and
# controllers, routers and handlers imported by name from domain modules
# (`app/asgi.py`) are served under every enclosing `Router(path=)`.
expected_endpoints = [
  Endpoint.new("/v01-base/orders/{order_id}", "GET", [Param.new("order_id", "", "path")]),
  Endpoint.new("/v01-base/catalog/items", "GET"),
  Endpoint.new("/u01-api/login", "POST"),
  Endpoint.new("/u01-api/users/", "GET"),
  Endpoint.new("/u02-v2/teams", "GET"),
  Endpoint.new("/u02-v2/team-router/members", "GET"),
  Endpoint.new("/u02-v2/ping", "GET"),
]

FunctionalTester.new("fixtures/python/litestar_router_composition/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
