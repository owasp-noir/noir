require "../../func_spec.cr"

expected_endpoints = [
  # api.hurl — the issue #2912 example.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/login", "POST", [
    Param.new("user", "bob", "json"),
    Param.new("password", "x", "json"),
  ]),
  Endpoint.new("/api/users/42", "PUT", [
    Param.new("force", "true", "query"),
    Param.new("Authorization", "Bearer {{token}}", "header"),
  ]),
  # sections.hurl — request sections, a templated host, response captures.
  Endpoint.new("/search", "GET", [
    Param.new("q", "noir", "query"),
    Param.new("page", "1", "query"),
    Param.new("session", "abc", "cookie"),
  ]),
  Endpoint.new("/upload", "POST", [
    Param.new("title", "report", "form"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/items/:item_id", "PATCH", [
    Param.new("X-Api-Key", "k1", "header"),
    Param.new("item_id", "", "path"),
    Param.new("name", "widget", "json"),
    Param.new("count", "", "json"),
  ]),
  Endpoint.new("/api/notes", "POST"),
]

FunctionalTester.new("fixtures/specification/hurl/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
