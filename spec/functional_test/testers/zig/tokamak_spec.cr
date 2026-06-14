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

FunctionalTester.new("fixtures/zig/tokamak/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
