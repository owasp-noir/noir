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
  # connect()->setMethods([...]) is honored instead of defaulting to GET
  Endpoint.new("/logout", "POST"),
  Endpoint.new("/sessions/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/sessions/{id}", "DELETE", [Param.new("id", "", "path")]),
  # prefix() opens a prefixed scope like scope()
  Endpoint.new("/groups/{id}", "GET", [Param.new("id", "", "path")]),
  # prefix() with ['path' => '/v1.0'] mounts under the path option, not /v10.
  # (The sibling `config/routes.php.twig` Bake template's `{{ plugin }}` routes
  # are ignored entirely — a `.twig` file is not a routes file.)
  Endpoint.new("/v1.0/status", "GET"),
  # Static Router facade form
  Endpoint.new("/legacy/ping", "GET"),
]

FunctionalTester.new("fixtures/php/cakephp/", {
  :techs     => 2,  # Detection still sees php_cakephp and php_pure
  :endpoints => 18, # Analysis suppresses redundant php_pure file endpoints
}, expected_endpoints).perform_tests
