require "../../func_spec.cr"

# Regression test for --include-callee on Tornado. Covers the three
# Tornado handler-resolution paths that exist today:
#
#   - UsersHandler  — defined in the same file as `Application(...)`
#                      (local class lookup via
#                      `extract_endpoints_from_class_in_file`).
#   - ProfileHandler — imported from a sibling module
#                      (`from handlers import ProfileHandler`), resolved
#                      via the import map; exercises the
#                      `async def get` shape so callee extraction
#                      handles both sync and async handler methods.
#
# Line assertions lock the `parse_code_block(lines[def..])` body-start
# convention used by the helper — body row 0 is the def line, callee
# line = def_line + tree-sitter-row + 1.
expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("self.get_body_argument", line: 9))
    ep.push_callee(Callee.new("save_user", line: 10))
    ep.push_callee(Callee.new("audit_log", line: 11))
    ep.push_callee(Callee.new("self.write", line: 12))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_profile", line: 8))
    ep.push_callee(Callee.new("audit_log", line: 9))
    ep.push_callee(Callee.new("self.write", line: 10))
  end,
]

FunctionalTester.new("fixtures/python/tornado_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
