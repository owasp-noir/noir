require "../../func_spec.cr"

# An HTTP *client* receiver is not a router. `request.get(url, opts)` in
# a test file carries the same tokens as `router.get(path, handler)` — an
# identifier, a verb, a path and a second argument — so the handler-shape
# heuristic keeps it. The receiver name is what separates them: nothing
# in these files builds a router called `request`. On NodeBB this shape
# put 11 endpoints that no server serves into the report.
expected_endpoints = [
  Endpoint.new("/api/users/:uid", "GET"),
  Endpoint.new("/api/users", "POST"),
]

FunctionalTester.new("fixtures/js/express_client_receiver/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
