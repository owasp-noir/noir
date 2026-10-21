require "../../func_spec.cr"

# Dify's wiring: each controller package declares its own `bp` Blueprint
# with a url_prefix, mounts an in-repo `ExternalApi(Api)` subclass on it and
# adds a `Namespace(path="/")` whose routes live in other modules. The URL
# is blueprint url_prefix + namespace path + route, per package.
expected_endpoints = [
  Endpoint.new("/console/api/workspaces/current/members", "GET"),
  Endpoint.new("/console/api/explore/banners", "GET"),
  Endpoint.new("/v1/parameters", "GET"),
]

FunctionalTester.new("fixtures/python/flask_restx_api_subclass/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
