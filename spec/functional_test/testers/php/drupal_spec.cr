require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/example", "GET"),
  Endpoint.new("/example/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/example/submit", "POST"),
  Endpoint.new("/admin/config/example/settings", "GET"),
  Endpoint.new("/node/{node}/example/{revision}", "GET", [Param.new("node", "", "path"), Param.new("revision", "", "path")]),
  Endpoint.new("/node/{node}/example/{revision}", "POST", [Param.new("node", "", "path"), Param.new("revision", "", "path")]),
]

FunctionalTester.new("fixtures/php/drupal/", {
  :techs     => 2, # php_drupal + php_pure (suppressed in analysis)
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
