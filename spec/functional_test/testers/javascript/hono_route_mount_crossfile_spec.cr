require "../../func_spec.cr"

# Hono mounts an imported sub-app on an anonymous fluent chain
# (`export default new Hono().route('/api', TodoAPI)`). The child file's
# routes inherit the `/api` prefix even though there is no named caller
# for the mount call to bind to.
expected_endpoints = [
  Endpoint.new("/api/todos", "GET"),
  Endpoint.new("/api/todos", "POST"),
  Endpoint.new("/api/todos/:id", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/hono_route_mount_crossfile/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
