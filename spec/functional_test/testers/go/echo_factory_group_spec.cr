require "../../func_spec.cr"

# The wiring file builds `v1 := r.Group("/api")` on `router.New()` and does
# not import echo. The prefix still has to reach `h.Register(v1)` and
# `handler.NewHTTP(h, v1)`. `metrics/client.go` has a path-shaped `.Group`
# and a `.GET` but is not an Echo package, so it contributes nothing.
expected_endpoints = [
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/tags", "GET"),
  Endpoint.new("/api/me", "GET"),
]

FunctionalTester.new("fixtures/go/echo_factory_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
