require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/public/secret.html", "GET"),
  Endpoint.new("/group/users", "GET"),
  Endpoint.new("/group/v1/migration", "GET"),
  # Route path without leading "/" under a Group("/"). Regression guard
  # for the gin-gonic/examples/basic pattern.
  Endpoint.new("/admin", "POST"),
  Endpoint.new("/mixed-get", "GET"),
  Endpoint.new("/mixed-post", "POST", [
    Param.new("field1", "", "form"),
  ]),
  Endpoint.new("/mixed-put", "PUT"),
  Endpoint.new("/mixed-delete", "DELETE"),
  Endpoint.new("/multiline", "GET", [
    Param.new("ml_param", "", "query"),
  ]),
  # handlers.go: PATCH method with path param
  Endpoint.new("/items/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  # handlers.go: multiple query params with DefaultQuery
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  # handlers.go: handler reference (non-inline)
  Endpoint.new("/healthz", "GET"),
  # handlers.go: deeply nested groups with form param
  Endpoint.new("/api/v2/data", "POST", [
    Param.new("payload", "", "form"),
  ]),
  # handlers.go: POST with header and form
  Endpoint.new("/webhook", "POST", [
    Param.new("X-Webhook-Secret", "", "header"),
    Param.new("event", "", "form"),
  ]),
  # handlers.go: cookie and query param combined
  Endpoint.new("/profile", "GET", [
    Param.new("session_id", "", "cookie"),
    Param.new("tab", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/gin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
