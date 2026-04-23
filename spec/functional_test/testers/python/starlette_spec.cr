require "../../func_spec.cr"

submit_params = [
  Param.new("body", "", "json"),
  Param.new("name", "", "query"),
  Param.new("X-Token", "", "header"),
  Param.new("session", "", "cookie"),
]

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/submit", "GET", submit_params),
  Endpoint.new("/submit", "POST", submit_params),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/upload", "POST", [Param.new("body", "", "form")]),
  Endpoint.new("/profile/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/python/starlette/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
