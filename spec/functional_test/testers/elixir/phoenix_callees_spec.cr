require "../../func_spec.cr"

users_index = Endpoint.new("/users", "GET", [
  Param.new("page", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService.list", line: 6))
  ep.push_callee(Callee.new("AuditLog.write", line: 7))
  ep.push_callee(Callee.new("JsonPresenter.render", line: 8))
  ep.push_callee(Callee.new("json", line: 8))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("UserPayload.from_conn", line: 12))
  ep.push_callee(Callee.new("UserService.create", line: 13))
  ep.push_callee(Callee.new("put_status", line: 15))
  ep.push_callee(Callee.new("json", line: 16))
  ep.push_callee(Callee.new("render_user", line: 16))
end

posts_index = Endpoint.new("/posts", "GET", [
  Param.new("category", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("PostQuery.list", line: 6))
  ep.push_callee(Callee.new("PostPresenter.render", line: 7))
  ep.push_callee(Callee.new("render", line: 7))
end

posts_show = Endpoint.new("/posts/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("PostQuery.find", line: 11))
  ep.push_callee(Callee.new("AuditLog.read_post", line: 12))
  ep.push_callee(Callee.new("PostPresenter.render", line: 13))
  ep.push_callee(Callee.new("render", line: 13))
end

expected_endpoints = [
  users_index,
  users_create,
  posts_index,
  posts_show,
]

FunctionalTester.new("fixtures/elixir/phoenix_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("elixir_phoenix"),
}).perform_tests
