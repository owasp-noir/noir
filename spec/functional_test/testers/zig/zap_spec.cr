require "../../func_spec.cr"

def zap_endpoint(url, method, callees = [] of Callee)
  endpoint = Endpoint.new(url, method)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

expected_endpoints = [] of Endpoint

# Endpoint structs — verbs come from the struct methods, the path from a
# field default (`/health`) or a project-wide `init("/users")` binding.
expected_endpoints << zap_endpoint("/health", "GET", [Callee.new("r.sendBody")])
expected_endpoints << zap_endpoint("/users", "GET", [Callee.new("listUsers")])
expected_endpoints << zap_endpoint("/users", "POST", [Callee.new("createUser")])

# Router handle_func / handle_func_unbound routes.
expected_endpoints << zap_endpoint("/stats", "GET", [Callee.new("r.sendJson")])
expected_endpoints << zap_endpoint("/ping", "GET", [Callee.new("r.sendBody")])

FunctionalTester.new("fixtures/zig/zap/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
