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
  Endpoint.new("/invoices/view/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/invoices/add", "POST"),
]

FunctionalTester.new("fixtures/php/phalcon_micro/", {
  :techs     => 2, # Detection still sees php_phalcon and php_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
