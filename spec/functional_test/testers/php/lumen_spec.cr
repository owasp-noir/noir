require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/login", "GET", [Param.new("email", "", "form")]),
  Endpoint.new("/login", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/api/v1/me", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/api/v1/items", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/api/v1/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/php/lumen/", {
  :techs     => 3,  # Detection sees php_lumen, php_laravel (shared signal), and php_pure
  :endpoints => 11, # Analysis drops the redundant Laravel run and php_pure file endpoint
}, expected_endpoints).perform_tests
