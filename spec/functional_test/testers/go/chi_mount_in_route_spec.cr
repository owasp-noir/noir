require "../../func_spec.cr"

# `r.Mount("/admin", adminRouter())` inside `r.Route("/api", ...)` /
# `r.Route("/v1", ...)` closures serves the sub-router under the closures'
# prefix too, at any depth, also for a Mount inside a `Route` of a mounted
# router (`/jobs` + `/queue`). A top-level Mount keeps its own prefix only.
# The endpoint count fails if a route is also reported without the prefix.
expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/api/v1/me", "GET"),
  Endpoint.new("/api/v1/admin/users", "GET"),
  Endpoint.new("/api/v1/admin/users/{userID}", "DELETE", [Param.new("userID", "", "path")]),
  Endpoint.new("/api/v1/admin/jobs/queue/flush", "POST"),
  Endpoint.new("/api/internal/metrics", "GET"),
  Endpoint.new("/debug/vars", "GET"),
]

FunctionalTester.new("fixtures/go/chi_mount_in_route/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
