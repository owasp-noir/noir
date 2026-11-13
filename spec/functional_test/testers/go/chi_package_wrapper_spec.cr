require "../../func_spec.cr"

# routes.go never imports chi: it registers through the package's own
# `*router` wrapper (supabase/auth's shape, #3577). The look-alike calls in
# store.go and the `flags.Get` lookup in routes.go are not on the wrapper
# and must stay out; routes_test.go is a test file.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users", "POST"),
  Endpoint.new("/admin/audit/events", "GET"),
  Endpoint.new("/user/profile", "GET"),
]

FunctionalTester.new("fixtures/go/chi_package_wrapper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
