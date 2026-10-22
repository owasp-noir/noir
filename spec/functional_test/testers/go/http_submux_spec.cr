require "../../func_spec.cr"

# `mux.Handle("/v1/", http.StripPrefix("/v1", v1))` mounts the ServeMux `v1`:
# its routes take the stripped prefix (nested mounts compose) and the mount
# registration itself is not a route.
expected_endpoints = [
  Endpoint.new("/v1/users/{id}", "GET"),
  Endpoint.new("/v1/users", "POST"),
  Endpoint.new("/v1/admin/stats", "GET"),
  Endpoint.new("/healthz", "GET"),
]

FunctionalTester.new("fixtures/go/http_submux/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
