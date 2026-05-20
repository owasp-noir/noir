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
  Endpoint.new("/api/v1/admin/settings", "PUT", [Param.new("value", "", "form")]),
  Endpoint.new("/api/v1/admin/settings", "PATCH", [Param.new("value", "", "form")]),
]

FunctionalTester.new("fixtures/php/lumen/", {
  :techs     => 3,  # Detection sees php_lumen, php_laravel (shared signal), and php_pure
  :endpoints => 13, # Analysis drops the redundant Laravel run and php_pure file endpoint
}, expected_endpoints).perform_tests

describe "Lumen analyzer filter" do
  it "drops php_laravel when php_lumen is detected so the redundant pass is skipped" do
    techs = ["php_lumen", "php_laravel", "php_pure"]
    filter_redundant_generic_techs(techs).should eq ["php_lumen"]
  end
end
