require "../../func_spec.cr"

# Laravel functional test - focusing on core functionality
# The test verifies Laravel detection and basic endpoint analysis
expected_endpoints = [
  # Core Laravel routes that are definitely working
  Endpoint.new("/", "GET"),
  Endpoint.new("/dashboard", "GET"),
  Endpoint.new("/terms", "GET"),
  Endpoint.new("/legacy-dashboard", "GET"),
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
  Endpoint.new("/photos", "GET"),
  Endpoint.new("/photos/{photo}", "GET", [Param.new("photo", "", "path")]),
  Endpoint.new("/admin/widgets", "GET"),
  Endpoint.new("/admin/widgets/{widget}", "GET", [Param.new("widget", "", "path")]),
  Endpoint.new("/admin/widgets/{widget}", "PATCH", [Param.new("widget", "", "path")]),
  Endpoint.new("/user", "GET"),
  Endpoint.new("/admin/settings", "GET"),
  Endpoint.new("/admin/settings", "POST"),
  Endpoint.new("/me", "GET"),
  Endpoint.new("/api/v1/profile", "GET"),
  Endpoint.new("/api/v1/profile", "POST"),
  Endpoint.new("/api/v1/tokens", "GET"),
  Endpoint.new("/api/v1/tokens/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/reports/daily", "GET"),
  Endpoint.new("/tenant/{tenant}/dashboard", "GET", [Param.new("tenant", "", "path")]),
]

FunctionalTester.new("fixtures/php/laravel/", {
  :techs     => 2,  # Detection still sees both php_laravel and php_pure
  :endpoints => 62, # Analysis suppresses redundant php_pure and unprefixed group endpoints
}, expected_endpoints).perform_tests
