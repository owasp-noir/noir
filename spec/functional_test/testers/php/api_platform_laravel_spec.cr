require "../../func_spec.cr"

# api-platform/laravel mounts resources under its packaged `/api` route prefix
# when config/api-platform.php has not been published; an explicit
# `routePrefix` replaces it.
expected_endpoints = [
  Endpoint.new("/api/authors", "GET"),
  Endpoint.new("/api/authors/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/calculate", "POST"),
]

FunctionalTester.new("fixtures/php/api_platform_laravel/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("php_api_platform"),
}).perform_tests
