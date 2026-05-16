require "../../func_spec.cr"

# Regression test for --include-callee on Gin (first cross-language
# wiring of #1366). Covers the three handler-resolution paths:
#
#   - POST /users          — named handler `createUser` defined in a
#                            sibling file (`handlers.go`). Exercises
#                            the cross-file lookup via
#                            `GoCalleeExtractor.collect_function_bodies`
#                            and confirms callee lines/paths point at
#                            the sibling, not main.go.
#   - GET /healthz         — inline `func(c *gin.Context) { … }`
#                            closure handler in main.go. Walks the
#                            func_literal body in place; no cross-file
#                            resolution needed.
#   - GET /profile         — named handler `listProfile` also in
#                            handlers.go; locks in that multiple named
#                            handlers in the same sibling file each
#                            scope to their own body.
#
# Line assertions verify that `start_row` arithmetic from the wrapped
# external parse maps back to the original file's lines. Bare same-package
# callees (saveUser, auditLog, buildProfile) resolve to their definition in
# helpers.go; selector calls (c.PostForm, c.JSON) stay at the call-site.
helpers_path = "./spec/functional_test/fixtures/go/gin_callees/helpers.go"

expected_endpoints = [
  # Note: Gin's existing PostForm/Query/GetHeader param extraction is
  # file-local — it scans the same file as the route declaration. Since
  # this endpoint's handler lives in handlers.go, the `c.PostForm("name")`
  # call there is invisible to the param extractor. The callee list IS
  # still populated because callee resolution follows the cross-file
  # handler binding; the two features are intentionally orthogonal.
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.PostForm", line: 8))
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
]

FunctionalTester.new("fixtures/go/gin_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
