require "../../func_spec.cr"

# Factory-built blueprints take the url_prefix their registration gives,
# including one mounted on a factory blueprint declared in another file.
expected_endpoints = [
  Endpoint.new("/tags/list", "GET"),
  Endpoint.new("/settings/general", "GET"),
  Endpoint.new("/settings/ai/models", "GET"),
  Endpoint.new("/mcp/v1/", "POST"),
  Endpoint.new("/h", "GET"),
  Endpoint.new("/rss/feed", "GET"),
  Endpoint.new("/pa", "GET"),
  Endpoint.new("/pb", "GET"),
  Endpoint.new("/A/alpha", "GET"),
  Endpoint.new("/B/beta", "GET"),
  Endpoint.new("/F/alpha", "GET"),
]

FunctionalTester.new("fixtures/python/flask_blueprint_factory/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
