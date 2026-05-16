require "../../func_spec.cr"

# Regression test for --include-callee on Goyave (#1366). Goyave
# doesn't use the route extractor's cross-file group fixpoint, so the
# analyzer builds `file_contents` for the callee map via the dedicated
# `read_package_file_contents` helper in GoEngine — this spec confirms
# that path resolves cross-file handlers correctly.
#
# Coverage:
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`; the call `request.QueryParams.Get`
#                     exercises a 2-level selector chain (identifier
#                     → attribute → attribute), proving the dotted
#                     callee name is reconstructed cleanly.
#   - GET /healthz  — inline closure inside the `RegisterRoutes`
#                     closure (Goyave's idiom). Routes live inside a
#                     `func` closure on `server.RegisterRoutes(...)`,
#                     and the callee `response.JSON` shows up at the
#                     real line in main.go (line 19, not the
#                     RegisterRoutes wrapper line).
#   - GET /profile  — second named handler in handlers.go.
helpers_path = "./spec/functional_test/fixtures/go/goyave_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("request.QueryParams.Get", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("response.JSON", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("response.JSON", line: 19))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("response.JSON", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/goyave_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
