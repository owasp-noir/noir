require "../../func_spec.cr"

# Restify's object route spec accepts `url` as an alias for `path`:
#   server.get({ url: '/foo/:id', name: 'GetFoo' }, handler)
expected_endpoints = [
  Endpoint.new("/foo/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/bar", "POST"),
]

FunctionalTester.new("fixtures/javascript/restify_object_url/", {
  :techs     => 1,
  :endpoints => 2,
}, expected_endpoints).perform_tests
