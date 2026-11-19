require "../../func_spec.cr"

# register_rest_route() namespaces and routes held in a local variable,
# a class constant, a `define()`/`const` constant, or a double-quoted
# string that interpolates them.
expected_endpoints = [
  Endpoint.new("/wp-json/control/v1/ping", "GET"),
  Endpoint.new("/wp-json/myplugin/v3/status", "GET"),
  Endpoint.new("/wp-json/myplugin/legacy/status", "GET"),
  Endpoint.new("/wp-json/vendor/v1/route", "GET"),
  Endpoint.new("/wp-json/vendor/v1/route", "POST"),
  Endpoint.new("/wp-json/vendor/v1/route/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v2/settings", "POST"),
  Endpoint.new("/wp-json/myplugin/v2/flags", "GET"),
  Endpoint.new("/wp-json/myplugin/v4/books/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/wp-json/myplugin/v1/route/latest", "GET"),
]

FunctionalTester.new("fixtures/php/wordpress_route_constants/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
