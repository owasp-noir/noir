require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello/world", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "body"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  # A bound variable in the segment list is a path param.
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # `[<<"static">> | _]` — the tail matches every remaining segment.
  Endpoint.new("/static/*", "GET"),
]

FunctionalTester.new("fixtures/erlang/elli/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
