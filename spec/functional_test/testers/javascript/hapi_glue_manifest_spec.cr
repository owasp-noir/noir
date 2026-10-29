require "../../func_spec.cr"

# #3291: a Glue app is detected from its package.json alone (no `require('hapi')`
# in code), and the manifest's `routes.prefix` applies to the plugin it
# registers: Glue 4 `registrations[].options.routes` (glue4/) and Glue 8
# `register.plugins[].routes`, from a separate manifest file (glue8/).
expected_endpoints = [
  Endpoint.new("/api/tags", "GET"),
  Endpoint.new("/api/articles/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/api/ping", "GET"),
]

FunctionalTester.new("fixtures/javascript/hapi_glue_manifest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
