require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/alice", "POST", [
    Param.new("query", "", "form"),
    Param.new("auth", "", "cookie"),
  ]),
  Endpoint.new("/", "GET", [Param.new("lang", "", "query")]),
  # Controller getters: form on POST/PUT/PATCH, query on GET and DELETE.
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/post", "POST", [Param.new("message", "", "form")]),
  Endpoint.new("/post", "PUT", [Param.new("n", "", "form")]),
  Endpoint.new("/post", "PATCH", [Param.new("on", "", "form")]),
  Endpoint.new("/post", "DELETE", [Param.new("id", "", "query")]),
]

FunctionalTester.new("fixtures/go/beego/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
