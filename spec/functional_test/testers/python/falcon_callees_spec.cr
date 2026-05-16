require "../../func_spec.cr"

# Regression test for --include-callee on Falcon. Falcon's class-based
# resource pattern means each responder (on_get / on_post / …) is a
# separate handler with its own body — the spec verifies that callees
# stay scoped to the right HTTP method and don't bleed across responders
# in the same class.
db_path = "./spec/functional_test/fixtures/python/falcon_callees/db.py"

expected_endpoints = [
  Endpoint.new("/items", "GET").tap do |ep|
    ep.push_callee(Callee.new("list_items", db_path, 1))
  end,

  Endpoint.new("/items", "POST").tap do |ep|
    ep.push_callee(Callee.new("save_item", db_path, 5))
  end,
]

FunctionalTester.new("fixtures/python/falcon_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
