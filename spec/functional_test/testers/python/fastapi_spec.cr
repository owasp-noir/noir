require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/query/param-required/int", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/items/{item_id}", "PUT", [Param.new("item_id", "", "path"), Param.new("name", "", "form"), Param.new("size", "", "form")]),
  Endpoint.new("/hidden_header", "GET", [Param.new("hidden_header", "", "header")]),
  Endpoint.new("/cookie_examples/", "GET", [Param.new("data", "", "cookie")]),
  Endpoint.new("/dummypath", "POST", [Param.new("dummy", "", "json")]),
  Endpoint.new("/main", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
