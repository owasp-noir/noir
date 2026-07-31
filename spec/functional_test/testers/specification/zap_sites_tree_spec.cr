require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/about/", "GET"),
  Endpoint.new("/zz", "GET"),
  Endpoint.new("/zz/", "DELETE"),
  # ZAP records the URL a node was reached with, query string included. Only
  # the path used to be kept, so every query parameter ZAP had already
  # discovered was thrown away.
  Endpoint.new("/111", "PUT", [Param.new("q", "", "query")]),
  Endpoint.new("/about/", "POST", [Param.new("data", "", "form"), Param.new("id", "", "form")]),
]

FunctionalTester.new("fixtures/specification/zap/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
