require "../../func_spec.cr"

# Regression test for --include-callee on Pyramid. The fixture exercises
# the @view_config + config.add_route pattern; the spec confirms the
# handler def line is threaded through emit_endpoints, so callee line
# numbers point at the call site inside the view body (not the route
# declaration line).
expected_endpoints = [
  Endpoint.new("/users/{uid}", "GET").tap do |ep|
    ep.push_callee(Callee.new("fetch_user"))
  end,
]

FunctionalTester.new("fixtures/python/pyramid_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
