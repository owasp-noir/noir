require "../../func_spec.cr"

# Regression test for --include-callee on Masonite. The fixture exercises
# the string controller binding + a same-file import; the spec confirms
# that a callee with a reachable imported definition resolves to the
# definition location instead of the call site inside the controller.
db_path = "./spec/functional_test/fixtures/python/masonite_callees/app/db.py"

expected_endpoints = [
  Endpoint.new("/users/{uid}", "GET", [
    Param.new("uid", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("fetch_user", db_path, 1))
  end,
]

FunctionalTester.new("fixtures/python/masonite_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
