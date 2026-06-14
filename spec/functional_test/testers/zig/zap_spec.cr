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

# `const Self = @This()` endpoint reached via the `Endpoints.Comments`
# namespace re-export and bound to `/comments` at the instantiation site —
# the binding overrides the dead `path = "/unused"` field default.
expected_endpoints << zap_endpoint("/comments", "GET", [Callee.new("listComments")])
expected_endpoints << zap_endpoint("/comments", "POST", [Callee.new("createComment")])

# Modern `zap.Endpoint.init(.{ .get = …, .post = … })` API — verbs from the
# init option fields, path from the `ProjectsEndpoint.init("/projects")`
# binding, callees from each bound handler's body.
expected_endpoints << zap_endpoint("/projects", "GET", [Callee.new("listProjects")])
expected_endpoints << zap_endpoint("/projects", "POST", [Callee.new("saveProject")])

# Router handle_func / handle_func_unbound routes.
expected_endpoints << zap_endpoint("/stats", "GET", [Callee.new("r.sendJson")])
expected_endpoints << zap_endpoint("/ping", "GET", [Callee.new("r.sendBody")])

FunctionalTester.new("fixtures/zig/zap/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
