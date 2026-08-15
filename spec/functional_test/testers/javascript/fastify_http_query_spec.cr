require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/search", "QUERY", [
    Param.new("q", "", "query"),
    Param.new("filter", "", "json"),
  ]),
  Endpoint.new("/advanced-search", "QUERY", [
    Param.new("term", "", "json"),
  ]),
  Endpoint.new("/items/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/items/:id", "QUERY", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/v1/plugin-query", "QUERY", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/v1/plugin-route", "QUERY"),
]

FunctionalTester.new("fixtures/javascript/fastify_http_query/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
