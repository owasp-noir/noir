require "../../func_spec.cr"

# Routes registered on a router or group returned by an accessor (#3596):
# `router.V1().POST(...)` through the calling file's import of another
# package, whose `func V1() *gin.RouterGroup` returns a group bound with
# `v1 = router.Group("/api/v1")`; `router.Router()` returning the engine; a
# `.Group(...)` chain off an accessor; and same-package `V1()` / `s.Admin()`.
# Calls of accessors declared with another result type (`config.Get()`,
# `store.Get()`, a resty `client.New()`, a `legacy.V1()` returning another
# package's `Engine`) and lookups on non-router values stay out.
expected_endpoints = [
  Endpoint.new("/api/v1/login", "POST", [Param.new("username", "", "form")]),
  Endpoint.new("/api/v1/me", "GET", [Param.new("fields", "", "query")]),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path"), Param.new("fields", "", "query")]),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/go/gin_router_accessor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
