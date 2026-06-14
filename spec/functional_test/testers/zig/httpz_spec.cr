require "../../func_spec.cr"

def httpz_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

id_param = [Param.new("id", "", "path")]

expected_endpoints = [] of Endpoint

expected_endpoints << httpz_endpoint("/", "GET", [] of Param, [Callee.new("res.write")])
expected_endpoints << httpz_endpoint("/users/:id", "GET", id_param, [
  Callee.new("req.param"),
  Callee.new("res.json"),
])
expected_endpoints << httpz_endpoint("/users", "POST", [] of Param, [Callee.new("userStore.insert")])
expected_endpoints << httpz_endpoint("/users/:id", "DELETE", id_param, [Callee.new("userStore.remove")])
# `router.all(...)` resolves to GET.
expected_endpoints << httpz_endpoint("/health", "GET", [] of Param, [Callee.new("res.write")])
# `router.method("QUERY", ...)` keeps the custom verb.
expected_endpoints << httpz_endpoint("/cache/:key", "QUERY", [Param.new("key", "", "path")], [Callee.new("cache.purge")])
# `@"…"` quoted-identifier handler (a reserved word) — the route is captured
# even though the `@"…"` name isn't indexed for body/callee lookup.
expected_endpoints << httpz_endpoint("/error", "GET")
# Group prefix composition.
expected_endpoints << httpz_endpoint("/admin/stats", "GET", [] of Param, [Callee.new("res.json")])
# Nested group prefix composition.
expected_endpoints << httpz_endpoint("/admin/v1/ping", "GET", [] of Param, [Callee.new("res.write")])

# Routes registered from a helper module that never names `httpz` — caught by
# the routing-signal file gate, with the local group prefix composed.
expected_endpoints << httpz_endpoint("/items/", "GET", [] of Param, [Callee.new("res.write")])
expected_endpoints << httpz_endpoint("/items/:id", "GET", [Param.new("id", "", "path")], [Callee.new("lookupItem")])
expected_endpoints << httpz_endpoint("/items/", "POST", [] of Param, [Callee.new("saveItem")])

# Two route sources must NOT add endpoints: the `/test-only` routes registered
# inside main.zig's `test { … }` block (unit-test fixtures), and the vendored
# `deps/httpz/src/tests/test_router.zig` framework copy's `/vendored-phantom`.
# The endpoint total therefore stays exactly the list above.

FunctionalTester.new("fixtures/zig/httpz/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
