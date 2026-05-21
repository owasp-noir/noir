require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("bio", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}/profile", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/ws", "GET"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{item_id}/tags", "POST", [
    Param.new("item_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/python/robyn/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
