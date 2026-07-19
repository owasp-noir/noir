require "../../func_spec.cr"

# FW/1 declares routes in Application.cfc as an array of single-key
# structs, keyed by an optional `$METHOD` followed by the pattern.
expected_endpoints = [
  # A verb prefix narrows the route to that method.
  Endpoint.new("/todo/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/todo/:id", "DELETE"),
  Endpoint.new("/todo", "POST"),

  # No `$` prefix: the route answers every method.
  Endpoint.new("/legacy/ping", "GET"),
  Endpoint.new("/legacy/ping", "POST"),
  Endpoint.new("/legacy/ping", "PUT"),
  Endpoint.new("/legacy/ping", "PATCH"),
  Endpoint.new("/legacy/ping", "DELETE"),
  Endpoint.new("/legacy/ping", "HEAD"),
  Endpoint.new("/legacy/ping", "OPTIONS"),

  # `hint` labels the entry rather than declaring a route, but the
  # route beside it still counts.
  Endpoint.new("/old/path", "GET"),
  Endpoint.new("/escaped/comma", "GET"),

  # `$RESOURCES` expands per framework/one.cfc's resourceRouteTemplates.
  # There is no `edit` route — FW/1 differs from Rails here.
  Endpoint.new("/dogs", "GET"),
  Endpoint.new("/dogs/new", "GET"),
  Endpoint.new("/dogs", "POST"),
  Endpoint.new("/dogs/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/dogs/:id", "PUT"),
  Endpoint.new("/dogs/:id", "PATCH"),
  Endpoint.new("/dogs/:id", "DELETE"),
]

FunctionalTester.new("fixtures/cfml/fw1/", {
  :techs     => 2, # Detection still sees cfml_fw1 and cfml_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
