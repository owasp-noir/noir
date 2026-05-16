require "../../func_spec.cr"

# Regression test for --include-callee on Bottle. The fixture's /report
# handler exercises a dotted-attribute call (request.query.get) plus a
# helper call (build_report), and verifies that an attribute *assignment*
# (response.content_type = "...") does NOT show up as a callee. /ping
# has zero calls in the body, locking in that empty callees stay empty.
app_path = "./spec/functional_test/fixtures/python/bottle_callees/app.py"
helpers_path = "./spec/functional_test/fixtures/python/bottle_callees/helpers.py"

expected_endpoints = [
  Endpoint.new("/report", "GET", [
    Param.new("user_id", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.query.get", app_path, 7))
    ep.push_callee(Callee.new("build_report", helpers_path, 1))
  end,

  Endpoint.new("/ping", "GET"),
]

FunctionalTester.new("fixtures/python/bottle_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
