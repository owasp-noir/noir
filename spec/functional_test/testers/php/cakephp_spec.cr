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
  :techs     => 2,  # php_cakephp and php_pure
  :endpoints => 14, # 12 CakePHP routes + 2 php_pure files (routes.php, ArticlesController.php)
}, expected_endpoints).perform_tests
