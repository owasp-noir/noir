require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/products/edit/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/products/save", "POST"),
  Endpoint.new("/products/update", "POST"),
  Endpoint.new("/products/update", "PUT"),
  Endpoint.new("/legacy/info", "GET"),
  Endpoint.new("/blog/save", "GET"),
  Endpoint.new("/blog/edit/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/products/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/products/save", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/api/products/save", "PUT", [Param.new("name", "", "form")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/show/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/php/phalcon_mvc/", {
  :techs     => 2, # Detection still sees php_phalcon and php_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
