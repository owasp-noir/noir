require "../../func_spec.cr"

# Router chains assembled inside a `vec![ ... ]` macro (the `impl
# Routers` shape). Verifies that routes hidden in a macro body are
# recovered, middleware (`.hoop`) and verb chaining between the path and
# the verb don't break detection, brace path params are captured, a
# scoped handler path still yields a route, and handler params/callees
# are enriched through the re-parsed macro path.
list_users = Endpoint.new("/api/users", "GET", [Param.new("query", "", "query")]).tap do |ep|
  ep.push_callee(Callee.new("UserService::all", line: 11))
  ep.push_callee(Callee.new("UserPresenter::render", line: 12))
end

create_user = Endpoint.new("/api/users", "POST", [Param.new("body", "", "json")]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 18))
end

get_user = Endpoint.new("/api/users/{id}", "GET", [
  Param.new("id", "", "path"),
  Param.new("X-Token", "", "header"),
])

serve_assets = Endpoint.new("/assets/{**path}", "GET", [Param.new("path", "", "path")])

expected_endpoints = [
  list_users,
  create_user,
  get_user,
  serve_assets,
]

FunctionalTester.new("fixtures/rust/salvo_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_salvo"),
}).perform_tests
