require "../../func_spec.cr"

# Regression test for --include-callee on Fiber (#1366). Mirrors the
# Gin/Echo coverage. Notable Fiber-specific shape: lowercase verb
# methods (`app.Get` / `app.Post`) and `*fiber.Ctx` receiver — the
# extractor handles both transparently because it keys off the verb
# field text without case-sensitive matching.
helpers_path = "./spec/functional_test/fixtures/go/fiber_callees/helpers.go"
remote_path = "./spec/functional_test/fixtures/go/fiber_callees/remote/handler.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.FormValue", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("c.JSON", line: 17))
  end,

  Endpoint.new("/remote/:id", "GET").tap do |ep|
    ep.push_callee(Callee.new("loadRemoteProfile", remote_path, 10))
    ep.push_callee(Callee.new("c.JSON", remote_path, 7))
  end,

  Endpoint.new("/remote-factory/:name", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildRemoteFactoryProfile", remote_path, 21))
    ep.push_callee(Callee.new("c.JSON", remote_path, 17))
  end,

  Endpoint.new("/remote-controller/:id", "GET").tap do |ep|
    ep.push_callee(Callee.new("loadRemoteProfile", remote_path, 10))
    ep.push_callee(Callee.new("c.JSON", remote_path, 33))
  end,
]

FunctionalTester.new("fixtures/go/fiber_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
