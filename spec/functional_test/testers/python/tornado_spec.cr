require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/auth", "POST", [Param.new("X-API-Key", "", "header"), Param.new("auth_token", "", "cookie")]),
  Endpoint.new("/api", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/api", "POST", [Param.new("", "", "json")]),
  Endpoint.new("/search", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/items(?:/(\\d+))?", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/admin", "GET", [Param.new("admin_token", "", "cookie")]),
  Endpoint.new("/admin", "DELETE"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/api/v2", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/api/v2", "POST", [Param.new("", "", "json")]),
  Endpoint.new("/triple-bracket", "GET"),
  Endpoint.new("/search/v2", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/nested-def", "POST", [Param.new("username", "", "form")]),
  Endpoint.new("/inner-class", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/inner-class", "DELETE"),
  Endpoint.new("/multiline-tuple", "GET"),
  Endpoint.new("/multiline-triple", "GET"),
]

FunctionalTester.new("fixtures/python/tornado/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
