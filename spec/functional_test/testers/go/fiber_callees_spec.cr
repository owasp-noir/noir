require "../../func_spec.cr"

# Regression test for --include-callee on Fiber (#1366). Mirrors the
# Gin/Echo coverage. Notable Fiber-specific shape: lowercase verb
# methods (`app.Get` / `app.Post`) and `*fiber.Ctx` receiver — the
# extractor handles both transparently because it keys off the verb
# field text without case-sensitive matching.
expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.FormValue", line: 8))
    ep.push_callee(Callee.new("saveUser", line: 9))
    ep.push_callee(Callee.new("auditLog", line: 10))
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", line: 15))
    ep.push_callee(Callee.new("auditLog", line: 16))
    ep.push_callee(Callee.new("c.JSON", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/fiber_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
