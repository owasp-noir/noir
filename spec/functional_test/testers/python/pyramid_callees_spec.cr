require "../../func_spec.cr"

# Regression test for --include-callee on Pyramid. The fixture exercises
# the @view_config + config.add_route pattern; the spec confirms that
# callees with reachable same-file or imported Python definitions resolve
# to the definition location instead of the call site inside the view.
db_path = "./spec/functional_test/fixtures/python/pyramid_callees/db.py"

expected_endpoints = [
  Endpoint.new("/users/{uid}", "GET").tap do |ep|
    ep.push_callee(Callee.new("fetch_user", db_path, 1))
  end,
]

FunctionalTester.new("fixtures/python/pyramid_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
