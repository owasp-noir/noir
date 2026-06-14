require "../../func_spec.cr"

def jetzig_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

id_param = [Param.new("id", "", "path")]

expected_endpoints = [] of Endpoint

# root.zig -> mounted at `/`.
expected_endpoints << jetzig_endpoint("/", "GET")
expected_endpoints << jetzig_endpoint("/:id", "GET", id_param)
expected_endpoints << jetzig_endpoint("/:id/edit", "GET", id_param)

# posts.zig -> full resourceful set under `/posts`.
expected_endpoints << jetzig_endpoint("/posts", "GET", [] of Param, [
  Callee.new("Post.findAll"),
  Callee.new("data.put"),
  Callee.new("request.render"),
])
expected_endpoints << jetzig_endpoint("/posts/:id", "GET", id_param)
expected_endpoints << jetzig_endpoint("/posts/new", "GET")
expected_endpoints << jetzig_endpoint("/posts/:id/edit", "GET", id_param)
expected_endpoints << jetzig_endpoint("/posts", "POST", [Param.new("title", "", "query")], [
  Callee.new("request.params"),
  Callee.new("params.get"),
  Callee.new("Post.create"),
])
expected_endpoints << jetzig_endpoint("/posts/:id", "PUT", id_param)
expected_endpoints << jetzig_endpoint("/posts/:id", "PATCH", id_param)
expected_endpoints << jetzig_endpoint("/posts/:id", "DELETE", id_param, [
  Callee.new("Post.destroy"),
  Callee.new("request.render"),
])

# admin/users.zig -> nested view mounted at `/admin/users`.
expected_endpoints << jetzig_endpoint("/admin/users", "GET")
expected_endpoints << jetzig_endpoint("/admin/users/:id", "GET", id_param)

# Explicit `app.route(...)` custom routes in main.zig. The view module under
# `app/api/` is resolved cross-file for callees; the commented `.DELETE`
# registration is excluded.
expected_endpoints << jetzig_endpoint("/api/products", "GET", [] of Param, [
  Callee.new("Product.findAll"),
  Callee.new("request.render"),
])
expected_endpoints << jetzig_endpoint("/api/products/:id", "GET", id_param, [
  Callee.new("Product.find"),
])
expected_endpoints << jetzig_endpoint("/api/products", "POST", [] of Param, [
  Callee.new("Product.create"),
])

FunctionalTester.new("fixtures/zig/jetzig/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
