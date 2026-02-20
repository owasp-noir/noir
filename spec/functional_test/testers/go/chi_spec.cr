require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/articles/", "POST"),
  Endpoint.new("/articles/search", "GET"),
  Endpoint.new("/articles/{articleSlug:[a-z-]+}", "GET", [Param.new("articleSlug", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "GET", [Param.new("articleID", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "PUT", [Param.new("articleID", "", "path")]),
  Endpoint.new("/articles/{articleID}/", "DELETE", [Param.new("articleID", "", "path")]),
  Endpoint.new("/admin/", "GET"),
  Endpoint.new("/admin/accounts", "GET"),
  Endpoint.new("/search-test", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/login-test", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/register-test", "POST", [
    Param.new("email", "", "form"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/api-test", "GET", [
    Param.new("X-API-Key", "", "header"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/profile-test", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("auth_token", "", "cookie"),
  ]),
  Endpoint.new("/multiline", "GET"),
  Endpoint.new("/uppercase", "GET"),
  Endpoint.new("/uppercase-post", "POST"),
  Endpoint.new("/grouped", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/admin/settings/", "GET"),
  Endpoint.new("/admin/settings/", "PUT"),
  Endpoint.new("/admin/webhook", "POST"),
]

FunctionalTester.new("fixtures/go/chi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
