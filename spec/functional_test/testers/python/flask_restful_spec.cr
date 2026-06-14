require "../../func_spec.cr"

# flask_restful / flask-restx register class-based `Resource`s via
# `api.add_resource(ResourceClass, "/url"[, "/url2"], ...)`. Each Resource
# exposes one endpoint per HTTP-verb method it defines, the class is often
# imported from another module, and apps frequently wrap add_resource in an
# Api subclass method (e.g. redash's add_org_resource). This fixture covers
# all three: same-file resolution, cross-file resolution, the wrapper alias,
# multi-URL registration and `<int:item_id>` path params.
expected_endpoints = [
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/items/<int:item_id>", "GET", [Param.new("item_id", "", "path")]),
  Endpoint.new("/items/<int:item_id>", "PUT", [Param.new("item_id", "", "path")]),
  Endpoint.new("/items/<int:item_id>", "DELETE", [Param.new("item_id", "", "path")]),
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/all", "GET"),
  Endpoint.new("/items/all", "POST"),
  Endpoint.new("/api/v2/health", "GET"),
]

FunctionalTester.new("fixtures/python/flask_restful/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
