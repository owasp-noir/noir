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
# Imported helper callees (save_user, audit_log, build_profile) resolve
# to their definitions in helpers.py; `self.*` calls stay at the
# call-site because they aren't bare module-level names.
app_path = "./spec/functional_test/fixtures/python/tornado_callees/app.py"
handlers_path = "./spec/functional_test/fixtures/python/tornado_callees/handlers.py"
helpers_path = "./spec/functional_test/fixtures/python/tornado_callees/helpers.py"

expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("self.get_body_argument", app_path, 9))
    ep.push_callee(Callee.new("save_user", helpers_path, 1))
    ep.push_callee(Callee.new("audit_log", helpers_path, 5))
    ep.push_callee(Callee.new("self.write", app_path, 12))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_profile", helpers_path, 9))
    ep.push_callee(Callee.new("audit_log", helpers_path, 5))
    ep.push_callee(Callee.new("self.write", handlers_path, 10))
  end,
]

FunctionalTester.new("fixtures/python/tornado_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
