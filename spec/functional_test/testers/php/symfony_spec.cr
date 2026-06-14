require "../../func_spec.cr"

expected_endpoints = [
  # From UserController annotations
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("search", "", "query"),
    Param.new("X-API-Key", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
    Param.new("Authorization", "", "header"),
    Param.new("avatar", "", "file"),
  ]),
  Endpoint.new("/api/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("Content-Type", "", "header"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # From ProductController attributes
  Endpoint.new("/api/products", "GET"),
  Endpoint.new("/api/products/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/api/products", "POST", [
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
    Param.new("category", "", "query"),
    Param.new("User-Agent", "", "header"),
    Param.new("image", "", "file"),
  ]),
  Endpoint.new("/api/products/{slug}", "PATCH", [
    Param.new("slug", "", "path"),
    Param.new("X-CSRF-Token", "", "header"),
    Param.new("preferences", "", "cookie"),
  ]),
  # From AdminController class-level prefix and named path attributes
  Endpoint.new("/api/admin/stats", "GET"),
  Endpoint.new("/api/admin/reports/{id}", "POST", [
    Param.new("id", "", "path"),
  ]),
  # From StorefrontController multi-line #[Route] attributes whose verbs are
  # `Request::METHOD_*` constants and whose `path:` sits after a newline.
  Endpoint.new("/account/login", "GET"),
  Endpoint.new("/account/login", "POST"),
  Endpoint.new("/account/order/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/account/order/{id}", "POST", [
    Param.new("id", "", "path"),
  ]),
  # From routes.yaml
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/docs", "GET"),
  Endpoint.new("/api/categories", "GET"),
  Endpoint.new("/api/categories", "POST"),
  Endpoint.new("/api/categories/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/categories/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/categories/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/search", "GET"),
  Endpoint.new("/webhooks/{provider}", "POST", [
    Param.new("provider", "", "path"),
  ]),
  Endpoint.new("/api/status-check", "GET"),
]

FunctionalTester.new("fixtures/php/symfony/", {
  :techs     => 2,  # Detection still sees php_symfony and php_pure
  :endpoints => 25, # Analysis suppresses redundant php_pure file endpoints
}, expected_endpoints).perform_tests
