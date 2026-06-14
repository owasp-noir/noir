require "../../func_spec.cr"

def tokamak_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

id_param = [Param.new("id", "", "path")]

expected_endpoints = [] of Endpoint

expected_endpoints << tokamak_endpoint("/", "GET", [] of Param, [Callee.new("greet")])
expected_endpoints << tokamak_endpoint("/users", "POST", [] of Param, [
  Callee.new("db.insert"),
  Callee.new("audit.log"),
])
# `.group("/api", …)` prefix.
expected_endpoints << tokamak_endpoint("/api/health", "GET")
# Nested `.group("/v1", …)` inherits `/api`.
expected_endpoints << tokamak_endpoint("/api/v1/items/:id", "GET", id_param, [Callee.new("store.fetch")])
expected_endpoints << tokamak_endpoint("/api/v1/items/:id", "DELETE", id_param, [Callee.new("store.remove")])

# `.router(widgets)` controller mount — the `@"METHOD /path"` handlers compose
# the enclosing `/api` group prefix.
expected_endpoints << tokamak_endpoint("/api/widgets", "GET", [] of Param, [Callee.new("listWidgets")])
expected_endpoints << tokamak_endpoint("/api/widgets", "POST", [] of Param, [Callee.new("createWidget")])
expected_endpoints << tokamak_endpoint("/api/widgets/:id", "GET", id_param, [Callee.new("findWidget")])

# Qualified struct mounts (`.router(resources.Public/.Private)`): the
# `pub const @"METHOD /path"` route bindings inherit only the `/admin` prefix
# of the mount selecting their enclosing struct. Handlers are defined
# elsewhere, so these carry no callees.
expected_endpoints << tokamak_endpoint("/admin/ping", "GET")
expected_endpoints << tokamak_endpoint("/admin/login", "POST")
expected_endpoints << tokamak_endpoint("/admin/sessions/:id", "DELETE", id_param)

# Value-form group `.group("/svc", .router(local))` mounting a same-file struct.
# The root handler collapses to `/svc` (no trailing slash).
expected_endpoints << tokamak_endpoint("/svc", "GET", [] of Param, [Callee.new("ping")])
expected_endpoints << tokamak_endpoint("/svc/sync", "POST", [] of Param, [Callee.new("worker.run")])

FunctionalTester.new("fixtures/zig/tokamak/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
