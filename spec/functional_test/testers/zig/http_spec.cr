require "../../func_spec.cr"

def zig_http_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

id_param = [Param.new("id", "", "path")]

expected_endpoints = [] of Endpoint

expected_endpoints << zig_http_endpoint("/", "GET", [] of Param, [Callee.new("request.respond")])
expected_endpoints << zig_http_endpoint("/users", "POST", [] of Param, [Callee.new("createUser")])
expected_endpoints << zig_http_endpoint("/users/:id", "GET", id_param, [Callee.new("getUser")])
expected_endpoints << zig_http_endpoint("/users/:id", "DELETE", id_param, [Callee.new("deleteUser")])
expected_endpoints << zig_http_endpoint("/users/:id", "PATCH", id_param, [Callee.new("updateUser")])
expected_endpoints << zig_http_endpoint("/health", "GET", [] of Param, [Callee.new("health")])

FunctionalTester.new("fixtures/zig/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
