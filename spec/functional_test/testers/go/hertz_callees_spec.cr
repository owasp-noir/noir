require "../../func_spec.cr"

# Regression test for --include-callee on Hertz (#1366). Mirrors
# Gin/Echo/Fiber. Hertz's handler signature takes `(c context.Context,
# ctx *app.RequestContext)`, so callees on the request context come
# back as `ctx.PostForm` / `ctx.JSON` rather than `c.JSON`.
#
# Note: this fixture does NOT exercise the `.Any("/path", ...)` verb
# expansion path on purpose — that's covered by the existing
# `hertz_spec.cr` route-extraction tests. Here we only need to confirm
# that the per-emit-endpoint callee push runs in both the ANY and the
# single-verb branches of `hertz.cr`. Adding an Any route would just
# re-state the same assertion N times.
#
# Also note `string(name)` in handlers.go is filtered by `BUILTINS` —
# Go primitive type-conversions don't surface as callees.
helpers_path = "./spec/functional_test/fixtures/go/hertz_callees/helpers.go"
remote_path = "./spec/functional_test/fixtures/go/hertz_callees/remote/feed.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("ctx.PostForm", line: 10))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.JSON", line: 13))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("ctx.JSON", line: 14))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.JSON", line: 19))
  end,

  Endpoint.new("/wrapped-feed", "GET").tap do |ep|
    ep.push_callee(Callee.new("loadFeed", remote_path, 14))
    ep.push_callee(Callee.new("ctx.JSON", remote_path, 11))
  end,
]

FunctionalTester.new("fixtures/go/hertz_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
