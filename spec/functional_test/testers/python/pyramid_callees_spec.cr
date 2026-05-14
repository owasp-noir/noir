require "../../func_spec.cr"

# Regression test for --include-callee on Pyramid. The fixture exercises
# the @view_config + config.add_route pattern; the spec confirms the
# handler def line is threaded through emit_endpoints AND that imported
# helpers are resolved to their definition location (db.py) rather than
# left at the view call site.
db_path = "./spec/functional_test/fixtures/python/pyramid_callees/db.py"

expected_endpoints = [
  Endpoint.new("/users/{uid}", "GET").tap do |ep|
    # `fetch_user` is imported from db.py where it's defined at line 1.
    # Without definition resolution the callee would point at line 9 of
    # app.py (the call site inside `user_detail`).
    ep.push_callee(Callee.new("fetch_user", db_path, 1))
  end,
]

FunctionalTester.new("fixtures/python/pyramid_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
