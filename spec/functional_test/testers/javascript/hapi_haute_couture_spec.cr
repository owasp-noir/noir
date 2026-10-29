require "../../func_spec.cr"

# #3291: haute-couture hands every `routes/` module's export to
# `server.route()`; a plain object and a `Helpers.withDefaults({...})` call
# are both route configs, and `options.handler` is read for params.
expected_endpoints = [
  Endpoint.new("/articles/{slug}", "PUT", [Param.new("slug", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/articles/{slug}", "DELETE", [Param.new("slug", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/hapi_haute_couture/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
