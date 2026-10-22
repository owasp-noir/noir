require "../../func_spec.cr"

# A Blueprint subclass (`class ApiBlueprint(Blueprint)`) is built with Sanic's
# constructor, so its url_prefix and version= shape the served URL just as they
# do for a plain Blueprint. The shared extractor already applied the prefix;
# the version has to follow, or the URL is half-composed (`/items/list`
# instead of `/v2/items/list`).
expected_endpoints = [
  Endpoint.new("/v2/items/list", "GET"),
  Endpoint.new("/v3/ping", "GET"),
]

FunctionalTester.new("fixtures/python/sanic_blueprint_subclass/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
