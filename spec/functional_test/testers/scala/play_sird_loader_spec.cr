require "../../func_spec.cr"

# Play SIRD routers built with `Router.from { ... }` in an
# `ApplicationLoader`, with no `conf/routes` naming them (#3268). An
# interpolated `withPrefix(s"/items/$name")` keeps `$name` as a segment.
expected_endpoints = [
  Endpoint.new("/health_check", "GET"),
  Endpoint.new("/items/:name/:version", "GET", [Param.new("name", "", "path"), Param.new("version", "", "path")]),
  Endpoint.new("/items/:name/-/refresh", "POST", [Param.new("name", "", "path")]),
]

FunctionalTester.new("fixtures/scala/play_sird_loader/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
