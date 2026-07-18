require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/echo", "GET", [
    Param.new("msg", "The message to echo", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "The username", "body"),
    Param.new("password", "The password", "body"),
  ]),
  Endpoint.new("/users/:id/posts/:post_id", "GET", [
    Param.new("id", "", "path"),
    Param.new("post_id", "", "path"),
    Param.new("limit", "Query limit", "query"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "The new name", "body"),
  ]),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/save/:key", "POST", [
    Param.new("key", "", "path"),
  ]),
  Endpoint.new("/direct", "GET"),
  Endpoint.new("/resource/:resource_id", "DELETE", [
    Param.new("resource_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/r/plumber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
