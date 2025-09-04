require "../../func_spec.cr"

# Laravel functional test - focusing on core functionality
# The test verifies Laravel detection and basic endpoint analysis
expected_endpoints = [
  # Core Laravel routes that are definitely working
  Endpoint.new("/", "GET"),
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/categories", "GET"),
  Endpoint.new("/categories", "POST"),
  Endpoint.new("/categories/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/contact", "GET"),
  Endpoint.new("/contact", "POST"),
  Endpoint.new("/webhook", "GET"),
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/products", "GET"),
  Endpoint.new("/products", "POST"),
]

FunctionalTester.new("fixtures/php/laravel/", {
  :techs     => 2,  # Both php_laravel and php_pure are detected
  :endpoints => 51, # Total detected endpoints
}, expected_endpoints).perform_tests
