require "../../func_spec.cr"

# Routes registered on router fields of a struct embedded from another
# package (#3597): `core.Controller{Echo *echo.Echo; Group *echo.Group}`
# embedded as `*core.Controller` in package `v2`, used as `c.Echo.GET(...)`
# and `c.Group.GET(...)`. The group's prefix is set in `core`'s constructor
# literal (`Group: e.Group("/api/v2")`), which the group map does not read,
# so `/health` stays unprefixed, as on any unread group. The embedded
# `*http.Client` field, an embedded `Echo` field of another type
# (`legacy.Base`) and lookups on non-router values stay out.
expected_endpoints = [
  Endpoint.new("/api/v2/audio/:id", "GET", [Param.new("id", "", "path"), Param.new("format", "", "query")]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/go/echo_router_embedded_field/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
