require "../../func_spec.cr"

# Regression test: chi apps routinely register routes with a constant or
# variable path argument (`const tokenPath = "/api/v2/token"` declared in
# a sibling file, used as `r.Get(tokenPath, h)`) and hang the router off a
# struct field (`s.router.Get(...)`). drakkan/sftpgo registers ~hundreds of
# routes this way; before this fix noir surfaced none of them.
#
# Coverage:
#   - GET /healthz   — selector receiver (`s.router`) + constant path +
#                      method-value handler (callee resolves through the
#                      method body to `writeOK`).
#   - GET /api/v2/token
#                    — bare receiver inside a `Group(func(r){...})` closure
#                      + constant path + method-value handler.
#   - POST /api/v2/admins/{username}/reset-password
#                    — `adminPath + "/{username}/reset-password"`
#                      concatenation of a path constant and a literal.
expected_endpoints = [
  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("writeOK"))
  end,
  Endpoint.new("/api/v2/token", "GET").tap do |ep|
    ep.push_callee(Callee.new("newToken"))
    ep.push_callee(Callee.new("w.Write"))
  end,
  Endpoint.new("/api/v2/admins/{username}/reset-password", "POST", [
    Param.new("username", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/go/chi_const_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
