require "../../func_spec.cr"

# Regression test for --include-callee on httprouter (#1366).
# Httprouter has two route shapes that the analyzer threads through
# `extract_routes(handle_method: "Handle")`:
#
#   1. Verb-method form: `r.GET("/x", h)` / `r.POST("/x", h)` etc.
#   2. Method-first form: `r.Handle("METHOD", "/x", h)`.
#
# `find_handler_arg` in `GoCalleeExtractor` picks the first non-string
# positional arg after the path string, which works for both shapes
# transparently (Handle has two leading strings, then the handler).
#
# httprouter extends `Analyzer` directly (not `GoEngine`), so the
# analyzer builds `file_contents` inline and uses the module-level
# twins on `GoCalleeExtractor` — this spec confirms that path
# resolves cross-file handlers correctly.
#
# Coverage:
#   - POST /users   — verb-method form, named handler in sibling
#                     `handlers.go`.
#   - GET /healthz  — verb-method form with inline closure handler.
#   - GET /profile  — method-first form `r.Handle("GET", "/profile",
#                     listProfile)`, second named handler in sibling
#                     file.
helpers_path = "./spec/functional_test/fixtures/go/httprouter_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("r.FormValue", line: 10))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("w.Write", line: 13))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("w.Write", line: 13))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("w.Write", line: 19))
  end,
]

FunctionalTester.new("fixtures/go/httprouter_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
