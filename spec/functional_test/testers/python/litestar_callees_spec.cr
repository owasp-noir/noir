require "../../func_spec.cr"

# Regression test for --include-callee on Litestar. Like FastAPI,
# Litestar's decorator-based handlers needed an explicit
# `parse_code_block` step at the emit site since the route extractor
# stops at the decorator. Verifies bare-identifier calls surface with
# correct line numbers and the per-handler `build_callees_from` hoist
# stays scoped to each emitted endpoint.
db_path = "./spec/functional_test/fixtures/python/litestar_callees/db.py"

expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/healthz", "GET"),
]

FunctionalTester.new("fixtures/python/litestar_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
