require "../../func_spec.cr"

# A Next.js project directory itself named `app` (`app/src/app/`,
# `apps/app/app/`): the router is the `app/` at the top of the project or in
# its `src/`, not the first `app/` in the path.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/api/ok", "GET"),
  Endpoint.new("/api/legacy", "GET"),
]

FunctionalTester.new("fixtures/javascript/nextjs_app_named_dir/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
