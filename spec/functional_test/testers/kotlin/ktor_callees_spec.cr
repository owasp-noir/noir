require "../../func_spec.cr"

# Regression test for --include-callee on Ktor (#1366). Unlike
# annotation-driven analyzers, Ktor declares routes via a DSL —
# `routing { get("/x") { ... } }` — so the handler body is a lambda
# `statements` node, not a `function_declaration`. The route
# extractor already locates that lambda for receive/parameter/header
# scanning; callee extraction reuses the same body via
# `KotlinCalleeExtractor.callees_in_lambda`.
#
# A nested routing DSL call (`route("/admin") { get("/dashboard") { ... } }`)
# must NOT leak the inner route's callees into the outer route's
# list — that's what `skip_routing: true` in the callee walker is
# for, and `/admin/dashboard` here exercises the boundary.
#
# Coverage:
#   - POST /users            — selector-on-identifier (`service.save`),
#                              bare-static (`AuditLog.write`), and
#                              chained-identifier (`call.respondText`)
#                              receivers.
#   - GET  /profile          — `this.foo` receiver shape.
#   - GET  /legacy           — chained-on-call (`getLegacy().toString()`)
#                              drops the outer `toString` and keeps
#                              only the inner `getLegacy`.
#   - GET  /admin/dashboard  — nested `route { get { ... } }` block;
#                              the parent `route("/admin")` lambda
#                              does NOT pick up `renderDashboard`,
#                              and the nested route emits it on its
#                              own.
expected_endpoints = [
  Endpoint.new("/users", "POST", [Param.new("name", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 12))
    ep.push_callee(Callee.new("AuditLog.write", line: 13))
    ep.push_callee(Callee.new("call.respondText", line: 14))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 18))
    ep.push_callee(Callee.new("AuditLog.write", line: 19))
    ep.push_callee(Callee.new("call.respondText", line: 20))
  end,

  Endpoint.new("/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 24))
    ep.push_callee(Callee.new("call.respondText", line: 25))
    ep.push_callee(Callee.new("getLegacy", line: 25))
  end,

  Endpoint.new("/admin/dashboard", "GET").tap do |ep|
    ep.push_callee(Callee.new("renderDashboard", line: 30))
  end,
]

FunctionalTester.new("fixtures/kotlin/ktor_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
