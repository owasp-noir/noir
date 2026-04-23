require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/login", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/login", "POST", [Param.new("session", "", "cookie")]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/api/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/api/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/php/slim/", {
  :techs     => 2,  # php_slim and php_pure
  :endpoints => 13, # 12 Slim routes + 1 php_pure GET for index.php
}, expected_endpoints).perform_tests
