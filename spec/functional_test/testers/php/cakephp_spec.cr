require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pages/*", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/Articles", "GET"),
  Endpoint.new("/Articles", "POST"),
  Endpoint.new("/Articles/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Articles/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/Articles/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/Articles/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/login", "POST"),
]

FunctionalTester.new("fixtures/php/cakephp/", {
  :techs     => 2,  # Detection still sees php_cakephp and php_pure
  :endpoints => 12, # Analysis suppresses redundant php_pure file endpoints
}, expected_endpoints).perform_tests
