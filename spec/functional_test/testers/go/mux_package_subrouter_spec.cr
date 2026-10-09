require "../../func_spec.cr"

# b.go re-scopes the package-level `r` (set to `/api` in main.go) with
# `r = r.PathPrefix("/v1").Subrouter()`. The handler's own `r *http.Request`
# param in b.go must not make that `r` look local and drop the `/api` seed.
expected_endpoints = [
  Endpoint.new("/api/v1/x", "GET"),
]

FunctionalTester.new("fixtures/go/mux_package_subrouter/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
